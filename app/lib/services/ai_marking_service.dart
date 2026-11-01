/// 「AI 打点」backend: ffmpeg audio/motion/tile extraction plus the DeepSeek
/// vision call, with no UI in here.
///
/// Steps, in the order the dialog runs them (docs/ai_marking.md):
///
/// 1. [AiMarkingService.extractAudio] — `-ac 1 -ar 16000 -f wav` into
///    `temp\ai_marking\<hash>.wav`;
/// 2. [AiMarkingService.extractMotion] — the 5 fps frame-difference metadata
///    (the primary channel) into `temp\ai_marking\<hash>.motion.txt`;
/// 3. [AudioSpikeDetector.detect] + [MotionSpikeDetector.detect] — pure Dart,
///    no ffmpeg, no model — then [mergeCandidateChannels] takes their union;
/// 4. [AiMarkingService.captureTiles] + [DeepSeekVisionClient.judgeImage] —
///    three 8-frame JPEGs per candidate, one per view, in one user message,
///    serial requests. Every view covers the whole 8 s window; a calibrated
///    source zooms the two user-boxed goal areas instead of the top/bottom
///    halves (docs/ai_marking.md §球门标定).
///
/// Everything here is cancellable: [AiMarkingService.cancel] kills the running
/// ffmpeg, [DeepSeekVisionClient.cancel] closes the in-flight HTTP connection.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/services/audio_spike_detector.dart';
import 'package:highlight_creator/services/goal_calibration.dart';
import 'package:highlight_creator/services/motion_spike_detector.dart';

/// What the model said about one candidate.
enum AiVerdict {
  /// The model called it a highlight; it goes into the project with rating 4.
  highlight,

  /// The model called it ordinary; it is listed but not written to a project.
  ordinary,

  /// Never judged — the endpoint refused images, the key was rejected, or this
  /// candidate alone failed. Kept, and saved with rating 2.
  unjudged,
}

/// Which detection channel(s) produced a candidate (docs/ai_marking.md
/// §Logging: `src=motion|audio|both`). Motion is the primary channel.
enum AiCandidateSource { motion, audio, both }

/// One candidate window plus whatever the model said about it.
///
/// The verdict fields are mutable because the dialog fills them in one
/// candidate at a time while the list is already on screen.
class AiSegment {
  AiSegment({
    required this.startMs,
    required this.endMs,
    required this.peakMs,
    required this.peakRms,
    this.motionPeak = 0,
    this.source = AiCandidateSource.audio,
  });

  final int startMs;
  final int endMs;

  /// The peak second the window was built around: `startMs` is normally
  /// `peakMs - 6 s` and `endMs` `peakMs + 2 s` (clipped at the file edges).
  /// The `cand` log prints `win = startMs - peakMs` from this.
  final int peakMs;

  /// Loudness of the event that produced this window, 0..1; 0 for a
  /// motion-only candidate.
  final double peakRms;

  /// Peak 1 s mean luma difference of the motion event, 0..255; 0 for an
  /// audio-only candidate. Only used to rank and truncate candidates.
  final double motionPeak;

  /// The channel(s) that caught this window — the evidence the log keeps.
  final AiCandidateSource source;

  AiVerdict verdict = AiVerdict.unjudged;

  /// One of `goal`, `save`, `shot`, `other`, `none`.
  String kind = 'none';

  /// One Chinese sentence from the model; empty when unjudged.
  String description = '';

  /// Why this one candidate was not judged, when it failed on its own.
  String? error;

  bool get passed => verdict == AiVerdict.highlight;

  int get durationMs => endMs - startMs;
}

/// The 8 s window both detectors build: `peak - 6 s` .. `peak + 2 s`. The
/// merge trims a long union back to the same shape, and all three tile views
/// sample the entire window (docs/ai_marking.md §B/§C).
const int _windowLeadMs = AudioSpikeDetector.leadMs;
const int _windowTailMs = AudioSpikeDetector.tailMs;

/// One candidate being merged from the two channels: the union of the windows
/// that overlap, plus which channels and peaks contributed.
class _Merged {
  _Merged.audio(AudioCandidate candidate)
      : startMs = candidate.startMs,
        endMs = candidate.endMs,
        audioPeak = candidate.peakRms,
        audioPeakMs = candidate.peakMs,
        motionPeak = 0,
        motionPeakMs = 0,
        fromAudio = true,
        fromMotion = false;

  _Merged.motion(MotionCandidate candidate)
      : startMs = candidate.startMs,
        endMs = candidate.endMs,
        audioPeak = 0,
        audioPeakMs = 0,
        motionPeak = candidate.peakMotion,
        motionPeakMs = candidate.peakMs,
        fromAudio = false,
        fromMotion = true;

  int startMs;
  int endMs;
  double audioPeak;
  int audioPeakMs;
  double motionPeak;
  int motionPeakMs;
  bool fromAudio;
  bool fromMotion;

  int get durationMs => endMs - startMs;

  void absorb(_Merged other) {
    startMs = math.min(startMs, other.startMs);
    endMs = math.max(endMs, other.endMs);
    if (other.audioPeak > audioPeak) {
      audioPeak = other.audioPeak;
      audioPeakMs = other.audioPeakMs;
    }
    if (other.motionPeak > motionPeak) {
      motionPeak = other.motionPeak;
      motionPeakMs = other.motionPeakMs;
    }
    fromAudio = fromAudio || other.fromAudio;
    fromMotion = fromMotion || other.fromMotion;
  }

  AiCandidateSource get source => fromAudio && fromMotion
      ? AiCandidateSource.both
      : (fromMotion ? AiCandidateSource.motion : AiCandidateSource.audio);
}

/// The union of the audio and motion candidates, one row per moment
/// (docs/ai_marking.md §画面运动通道):
///
/// * two windows overlapping by more than 50 % of the shorter one are the same
///   moment — their union becomes one candidate (`src=both`);
/// * a union longer than 8 s is trimmed back to `peak - 6 s .. peak + 2 s`
///   (motion peak when the row has motion, audio peak otherwise), so a merged
///   row keeps exactly the framing both detectors use — the decisive moment
///   sits 6/8 of the way in, with 2 s of aftermath behind it;
/// * more than [maxCandidates]: keep the `both` rows first, then by motion peak,
///   then by loudness, and finally put the survivors back in timeline order.
///
/// Audio-only rows keep `peakRms`, motion-only rows keep `motionPeak`; nothing
/// else in [AiSegment] is decided here.
List<AiSegment> mergeCandidateChannels({
  required List<AudioCandidate> audio,
  required List<MotionCandidate> motion,
  int maxCandidates = 60,
}) {
  final pending = <_Merged>[
    for (final candidate in audio) _Merged.audio(candidate),
    for (final candidate in motion) _Merged.motion(candidate),
  ]..sort((a, b) => a.startMs.compareTo(b.startMs));

  final merged = <_Merged>[];
  for (final item in pending) {
    _Merged? target;
    for (final row in merged) {
      if (_overlapRatio(row, item) > 0.5) {
        target = row;
        break;
      }
    }
    if (target == null) {
      merged.add(item);
    } else {
      target.absorb(item);
    }
  }
  // A union can grow far enough to touch a row closed before it, so fold the
  // groups until nothing overlaps any more. O(n²) on ≤ 120 rows.
  var stable = false;
  while (!stable) {
    stable = true;
    for (var i = 0; i < merged.length && stable; i++) {
      for (var j = i + 1; j < merged.length; j++) {
        if (_overlapRatio(merged[i], merged[j]) <= 0.5) continue;
        merged[i].absorb(merged[j]);
        merged.removeAt(j);
        stable = false;
        break;
      }
    }
  }

  final segments = <AiSegment>[];
  for (final row in merged) {
    var startMs = row.startMs;
    var endMs = row.endMs;
    if (endMs - startMs > _windowLeadMs + _windowTailMs) {
      final peakMs = row.fromMotion ? row.motionPeakMs : row.audioPeakMs;
      startMs = math.max(row.startMs, peakMs - _windowLeadMs);
      endMs = math.min(row.endMs, peakMs + _windowTailMs);
    }
    segments.add(AiSegment(
      startMs: startMs,
      endMs: endMs,
      peakMs: row.fromMotion ? row.motionPeakMs : row.audioPeakMs,
      peakRms: row.audioPeak,
      motionPeak: row.motionPeak,
      source: row.source,
    ));
  }

  if (segments.length > maxCandidates) {
    segments.sort((a, b) {
      final rank = _sourceRank(a.source).compareTo(_sourceRank(b.source));
      if (rank != 0) return rank;
      final motion = b.motionPeak.compareTo(a.motionPeak);
      if (motion != 0) return motion;
      return b.peakRms.compareTo(a.peakRms);
    });
    segments.removeRange(maxCandidates, segments.length);
  }
  segments.sort((a, b) => a.startMs.compareTo(b.startMs));
  return segments;
}

/// `both` before `motion` before `audio`: the rows two channels agree on are
/// the ones worth a request first.
int _sourceRank(AiCandidateSource source) => switch (source) {
      AiCandidateSource.both => 0,
      AiCandidateSource.motion => 1,
      AiCandidateSource.audio => 2,
    };

/// Overlap as a fraction of the shorter window: 8 s windows offset by 4.5 s
/// still count as the same moment.
double _overlapRatio(_Merged a, _Merged b) {
  final overlap = math.min(a.endMs, b.endMs) - math.max(a.startMs, b.startMs);
  if (overlap <= 0) return 0;
  final shorter = math.min(a.durationMs, b.durationMs);
  return shorter <= 0 ? 0 : overlap / shorter;
}

/// Base class for everything this feature throws; `toString()` is the message.
class AiMarkingException implements Exception {
  const AiMarkingException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The endpoint rejected the *shape* of the request: this model has no image
/// input. Every further candidate would fail the same way, so the caller stops.
class AiVisionUnsupported extends AiMarkingException {
  const AiVisionUnsupported(super.message);
}

/// 401/403: the key is wrong, so every further request would fail too.
class AiAuthFailure extends AiMarkingException {
  const AiAuthFailure(super.message);
}

/// The user pressed 取消.
class AiCancelled extends AiMarkingException {
  const AiCancelled() : super('cancelled');
}

/// ffmpeg plumbing: the WAV to measure and the tiles to look at.
class AiMarkingService {
  AiMarkingService({required this.ffmpegPath});

  final String ffmpegPath;

  Process? _process;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// `%USERPROFILE%\HighlightCreator\temp\ai_marking` — under `temp\` so the
  /// existing Cache files dialog already owns the cleanup story.
  static String get workDir =>
      '${AppPaths.tempDir}${Platform.pathSeparator}ai_marking';

  /// Stop the running ffmpeg. The pending step throws [AiCancelled].
  void cancel() {
    _cancelled = true;
    _process?.kill();
  }

  /// `<hash>` for the WAV: path + size + mtime, so a re-cut file with the same
  /// name does not reuse a stale recording.
  static String keyFor(String sourcePath) {
    var stamp = '';
    try {
      final stat = File(sourcePath).statSync();
      stamp = '${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    } catch (_) {
      // No stat: the path alone still gives a stable key.
    }
    return sha1
        .convert(utf8.encode('$sourcePath|$stamp'))
        .toString()
        .substring(0, 16);
  }

  /// A. Mono 16 kHz PCM16 WAV of [sourcePath], cached under the temp dir.
  Future<File> extractAudio(String sourcePath) async {
    final directory = Directory(workDir)..createSync(recursive: true);
    final wav = File(
        '${directory.path}${Platform.pathSeparator}${keyFor(sourcePath)}.wav');
    deleteQuietly(wav);
    try {
      await _run([
        '-y',
        '-loglevel',
        'error',
        '-i',
        sourcePath,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '16000',
        '-f',
        'wav',
        wav.path,
      ], what: 'audio extraction');
    } catch (_) {
      // A cancelled or failed ffmpeg leaves half a file behind; it must not be
      // mistaken for a finished one by a later run.
      deleteQuietly(wav);
      rethrow;
    }
    if (!wav.existsSync() || wav.lengthSync() <= 44) {
      throw const AiMarkingException('ffmpeg wrote an empty WAV');
    }
    return wav;
  }

  /// 画面运动: the 5 fps frame-difference series of [sourcePath], as ffmpeg's
  /// `metadata=print` text. The primary candidate channel
  /// (`MotionSpikeDetector.ffmpegArgs` builds the command, docs/ai_marking.md
  /// §画面运动通道).
  ///
  /// Runs through [_run] so a 取消 kills it like any other step; the caller
  /// parses it and deletes it.
  Future<File> extractMotion(String sourcePath) async {
    final directory = Directory(workDir)..createSync(recursive: true);
    final metadata = File('${directory.path}${Platform.pathSeparator}'
        '${keyFor(sourcePath)}.motion.txt');
    deleteQuietly(metadata);
    try {
      await _run(
        MotionSpikeDetector.ffmpegArgs(
          sourcePath: sourcePath,
          metadataPath: metadata.path,
        ),
        what: 'motion scan',
      );
    } catch (_) {
      // A cancelled or failed ffmpeg leaves a partial file behind; it must not
      // be parsed as a finished series by a later run.
      deleteQuietly(metadata);
      rethrow;
    }
    if (!metadata.existsSync() || metadata.lengthSync() == 0) {
      throw const AiMarkingException('ffmpeg wrote no motion metadata');
    }
    return metadata;
  }

  /// The still the 标定球门 dialog draws on: one JPEG at 30 % of the source,
  /// saved under `temp\ai_marking` so the existing Cache files dialog still
  /// owns the cleanup story.
  static String get calibrationFramePath =>
      '${workDir}${Platform.pathSeparator}calib_frame.jpg';

  /// A frame to draw the goal boxes on (docs/ai_marking.md §球门标定).
  ///
  /// `-ss` before `-i` seeks by keyframe instead of decoding the whole file,
  /// which is the difference between half a second and a minute on a 4K match.
  Future<File> extractCalibrationFrame({
    required String sourcePath,
    required int atMs,
  }) async {
    Directory(workDir).createSync(recursive: true);
    final jpg = File(calibrationFramePath);
    deleteQuietly(jpg);
    try {
      await _run([
        '-y',
        '-loglevel',
        'error',
        '-ss',
        _timestamp(math.max(0, atMs)),
        '-i',
        sourcePath,
        '-frames:v',
        '1',
        '-an',
        jpg.path,
      ], what: 'calibration frame capture');
    } catch (_) {
      deleteQuietly(jpg);
      rethrow;
    }
    if (!jpg.existsSync() || jpg.lengthSync() == 0) {
      throw const AiMarkingException('no calibration frame');
    }
    return jpg;
  }

  /// The three views one candidate is judged from, in the order the prompt
  /// names them: the whole frame (2×4), then the top and bottom halves at 2×
  /// width so action in the far distance is still legible when the tile is
  /// downscaled for the model (docs/ai_marking.md §C).
  ///
  /// `fps=1` is load-bearing: a tile holds 8 frame slots, so at 1 fps it spans
  /// the whole 8 s window. At the old `fps=2` view 1 covered only the first
  /// 4 s and the 2×2 zooms only 2 s — a one-second goal fell between tiles.
  static const List<String> tileFilters = [
    'fps=1,scale=448:-2,tile=2x4',
    'fps=1,crop=iw:ih/2:0:0,scale=896:-2,tile=4x2',
    'fps=1,crop=iw:ih/2:0:ih/2,scale=896:-2,tile=4x2',
  ];

  /// The same three views for a calibrated source (docs/ai_marking.md
  /// §球门标定): view 1 is still the whole frame, view 2 is 球门 1 and view 3
  /// is 球门 2 — both `fps=1 -> crop -> scale=896 -> tile=4x2`. With only one
  /// boxed goal view 3 stays the old bottom half, so the model still sees the
  /// rest of the pitch.
  static List<String> tileFiltersFor(GoalCalibration? calibration) {
    final rects = calibration?.rects ?? const <NormRect>[];
    if (rects.isEmpty) return tileFilters;
    return [
      tileFilters[0],
      'fps=1,${rects[0].cropFilter},scale=896:-2,tile=4x2',
      rects.length > 1
          ? 'fps=1,${rects[1].cropFilter},scale=896:-2,tile=4x2'
          : tileFilters[2],
    ];
  }

  /// C. The [tileFiltersFor] JPEGs of one candidate, all from the same window.
  ///
  /// Capture starts exactly at `segment.startMs`: the window is already
  /// `peak - 6 s .. peak + 2 s`, so the first six frames are context and the
  /// last two hold the aftermath. The old extra `-1 s` pre-roll made 8 frames
  /// at 1 fps stop one second before the window ended — right where the
  /// celebration is.
  Future<List<File>> captureTiles({
    required String sourcePath,
    required AiSegment segment,
    required String tag,
    GoalCalibration? calibration,
  }) async {
    final filters = tileFiltersFor(calibration);
    final directory = Directory(workDir)..createSync(recursive: true);
    final files = <File>[];
    try {
      for (var view = 0; view < filters.length; view++) {
        final jpg = File('${directory.path}${Platform.pathSeparator}'
            'tile-$tag-${view + 1}.jpg');
        deleteQuietly(jpg);
        files.add(jpg);
        await _run([
          '-y',
          '-loglevel',
          'error',
          '-ss',
          _timestamp(math.max(0, segment.startMs)),
          '-i',
          sourcePath,
          '-vf',
          filters[view],
          '-frames:v',
          '1',
          '-an',
          jpg.path,
        ], what: 'frame capture ${view + 1}/${filters.length}');
        if (!jpg.existsSync() || jpg.lengthSync() == 0) {
          throw AiMarkingException(
              'no frames around ${_timestamp(segment.startMs)}');
        }
      }
      return files;
    } catch (_) {
      // A failure on view 2 must not leave view 1 behind.
      for (final file in files) {
        deleteQuietly(file);
      }
      rethrow;
    }
  }

  Future<void> _run(List<String> arguments, {required String what}) async {
    if (_cancelled) throw const AiCancelled();
    final process = await _start(arguments);
    _process = process;
    // cancel() may have landed between the check above and the spawn.
    if (_cancelled) process.kill();

    // Drain stdout, keep the tail of stderr: that is where ffmpeg explains
    // itself, and the dialog surfaces the last lines on failure.
    final stdoutDone = process.stdout.drain<void>();
    final stderrLines = <String>[];
    final stderrDone = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      if (line.trim().isEmpty) return;
      stderrLines.add(line.trim());
      if (stderrLines.length > 40) stderrLines.removeAt(0);
    }).asFuture<void>();

    try {
      final code = await process.exitCode.timeout(const Duration(minutes: 10));
      await Future.wait<void>([stdoutDone, stderrDone]);
      if (_cancelled) throw const AiCancelled();
      if (code != 0) {
        throw AiMarkingException(
            '$what failed (ffmpeg exit $code): ${stderrLines.join(' | ')}');
      }
    } on TimeoutException {
      process.kill();
      throw AiMarkingException('$what timed out after 10 minutes');
    } finally {
      if (_cancelled) process.kill();
      _process = null;
    }
  }

  static String _timestamp(int ms) => (ms / 1000).toStringAsFixed(3);

  Future<Process> _start(List<String> arguments) async {
    try {
      return await Process.start(ffmpegPath, arguments);
    } on ProcessException catch (error) {
      throw AiMarkingException(
          'could not start ffmpeg ($ffmpegPath): ${error.message}');
    }
  }

  /// Best-effort delete: temp cleanup must never become a failure.
  static void deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

/// What one vision request answered.
class AiJudgement {
  const AiJudgement({
    required this.highlight,
    required this.kind,
    required this.description,
  });

  final bool highlight;
  final String kind;
  final String description;
}

/// What one HTTP attempt at [DeepSeekVisionClient.judgeImage] returned.
///
/// Deliberately holds no body text: the log needs the *shape* of an answer
/// (`finish_reason`, usage, how much of it was reasoning vs content), never the
/// reply itself (docs/ai_marking.md §Logging).
class AiAttempt {
  const AiAttempt({
    required this.attempt,
    required this.status,
    required this.maxTokens,
    required this.finishReason,
    required this.promptTokens,
    required this.completionTokens,
    required this.reasoningLen,
    required this.contentLen,
  });

  /// 1-based attempt number; 2 means the retry ran.
  final int attempt;

  final int status;
  final int maxTokens;

  /// `choices[0].finish_reason`, `'-'` when the reply carried none.
  final String finishReason;

  /// `usage.prompt_tokens`, null when the reply carried no usage object.
  final int? promptTokens;

  /// `usage.completion_tokens`, null when the reply carried no usage object.
  final int? completionTokens;

  /// `reasoning_content` length in characters, 0 when absent.
  final int reasoningLen;

  /// `message.content` length in characters, 0 when absent.
  final int contentLen;

  bool get retried => attempt > 1;
}

/// The OpenAI-compatible vision call, one request at a time.
///
/// Uses `dart:io` [HttpClient] on purpose: the project has no `http` package
/// and one POST does not justify adding it.
class DeepSeekVisionClient {
  DeepSeekVisionClient({
    this.endpoint = defaultEndpoint,
    this.timeout = const Duration(seconds: 90),
  });

  static const String defaultEndpoint =
      'https://api.deepseek.com/chat/completions';

  /// The model the dialog offers by default; both names accept the same API.
  static const String defaultModel = 'deepseek-flash';
  static const String altModel =
      'deepseek-v4-flash-vision-exp'; // legacy name, still accepted
  static const List<String> knownModels = [defaultModel, altModel];

  /// The kinds the prompt allows; anything else is folded into `other`.
  static const List<String> kinds = ['goal', 'save', 'shot', 'other', 'none'];

  /// The JSON contract from docs/ai_marking.md §C. The first image is a 2×4
  /// tile ("from left to right, top to bottom"); the other two are 2×2 zooms —
  /// of the top and bottom half for an uncalibrated source ([prompt]), or of
  /// the user-boxed goal areas ([promptFor]). The prompt has to say which.
  ///
  /// The bar is deliberately narrow — a goal, a keeper's save, or an
  /// unchallenged shot heading inside the frame. "A promising attack" was the
  /// old bar and it let every shot from a crowd through (docs/ai_marking.md
  /// §C). Anything short of those three is `highlight: false`.
  ///
  /// `json` is lowercase on purpose: JSON mode asks for the word `json` to
  /// appear in the prompt, and a checker that matches the literal word would
  /// miss `JSON`.
  static const String prompt = '下面是一个 8 秒候选片段的 3 张拼图,'
      '来自同一段足球比赛视频:\n'
      '图1:全场 8 帧,按 2 列 × 4 行排列,从左到右、从上到下按时间顺序;\n'
      '图2:画面上半部放大 8 帧(4 列 × 2 行),远端在画面上方时看这张;\n'
      '图3:画面下半部放大 8 帧(4 列 × 2 行),远端在画面下方时看这张。\n'
      '只有下面三种情况之一才算高光(highlight 为 true):\n'
      '1. 球进入球门(包括折射、补射);\n'
      '2. 门将做出扑救动作(倒地、扑出、没收);\n'
      '3. 无人防守下面对球门起脚,且球明显朝门框范围内飞去。\n'
      '仅仅在禁区外或人群中起脚、球被挡出或偏出、只是带球推进,都不算高光。\n'
      '若动作发生在远处/画面深处,以图2或图3为准;三张图都看不清时判为普通'
      '(highlight 为 false)。\n'
      '只输出一个 json 对象,不要代码块,不要解释:\n'
      '{"highlight": true 或 false, "kind": "goal|save|shot|other|none", '
      '"description": "一句中文描述"}\n'
      'description 只写画面里真实发生的动作,不要臆造比分或球员名字。';

  /// [prompt] for a source with only 球门 1 boxed: view 2 is the goal zoom,
  /// view 3 keeps the old bottom-half wording.
  static const String _promptOneGoal = '下面是一个 8 秒候选片段的 3 张拼图,'
      '来自同一段足球比赛视频:\n'
      '图1:全场 8 帧,按 2 列 × 4 行排列,从左到右、从上到下按时间顺序;\n'
      '图2:球门 1 区域的放大画面 8 帧(4 列 × 2 行),用户在这一帧上标定的球门就在这里;\n'
      '图3:画面下半部放大 8 帧(4 列 × 2 行),远端在画面下方时看这张。\n'
      '只有下面三种情况之一才算高光(highlight 为 true):\n'
      '1. 球进入球门(包括折射、补射);\n'
      '2. 门将做出扑救动作(倒地、扑出、没收);\n'
      '3. 无人防守下面对球门起脚,且球明显朝门框范围内飞去。\n'
      '仅仅在禁区外或人群中起脚、球被挡出或偏出、只是带球推进,都不算高光。\n'
      '进球或扑救发生在球门区域时以图2为准;其它远处/画面深处的动作以图2或图3为准;'
      '三张图都看不清时判为普通(highlight 为 false)。\n'
      '只输出一个 json 对象,不要代码块,不要解释:\n'
      '{"highlight": true 或 false, "kind": "goal|save|shot|other|none", '
      '"description": "一句中文描述"}\n'
      'description 只写画面里真实发生的动作,不要臆造比分或球员名字。';

  /// [prompt] for a source with both goals boxed. 图2/图3 are the two goal
  /// regions, so the model is told they are zoomed crops rather than halves.
  static const String _promptTwoGoals = '下面是一个 8 秒候选片段的 3 张拼图,'
      '来自同一段足球比赛视频:\n'
      '图1:全场 8 帧,按 2 列 × 4 行排列,从左到右、从上到下按时间顺序;\n'
      '图2:球门 1 区域的放大画面 8 帧(4 列 × 2 行);\n'
      '图3:球门 2 区域的放大画面 8 帧(4 列 × 2 行)。\n'
      '图2/图3 是两个球门区域的放大画面,是用户在这块固定机位的画面上标定的两处球门,'
      '进球与扑救只会发生在这两处。\n'
      '只有下面三种情况之一才算高光(highlight 为 true):\n'
      '1. 球进入球门(包括折射、补射);\n'
      '2. 门将做出扑救动作(倒地、扑出、没收);\n'
      '3. 无人防守下面对球门起脚,且球明显朝门框范围内飞去。\n'
      '仅仅在禁区外或人群中起脚、球被挡出或偏出、只是带球推进,都不算高光。\n'
      '若动作发生在远处/球门区域,以图2或图3为准;三张图都看不清时判为普通'
      '(highlight 为 false)。\n'
      '只输出一个 json 对象,不要代码块,不要解释:\n'
      '{"highlight": true 或 false, "kind": "goal|save|shot|other|none", '
      '"description": "一句中文描述"}\n'
      'description 只写画面里真实发生的动作,不要臆造比分或球员名字。';

  /// The instruction for this run: [prompt] when nothing is calibrated, the
  /// goal-region wording otherwise. [goals] is the number of usable boxes.
  static String promptFor({int goals = 0}) {
    if (goals <= 0) return prompt;
    return goals == 1 ? _promptOneGoal : _promptTwoGoals;
  }

  final String endpoint;
  final Duration timeout;

  HttpClient? _http;
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  /// Abort the in-flight request. [judgeImage] then throws [AiCancelled].
  void cancel() {
    _cancelled = true;
    _http?.close(force: true);
  }

  /// `max_tokens` for the first attempt at one candidate.
  ///
  /// A verdict is one short JSON object, so 512 is already generous; the old
  /// 300 was not the failure here — an empty `content` under a `length`
  /// finish_reason was (docs/ai_marking.md §C).
  static const int firstMaxTokens = 512;

  /// The cap for the single retry: [firstMaxTokens] doubled.
  static const int retryMaxTokens = 1024;

  /// The request body, as a pure function so it can be asserted in a unit test.
  ///
  /// One user message: the prompt plus one `image_url` per view, in the order
  /// [AiMarkingService.tileFiltersFor] produced them. Thinking is disabled below:
  /// the reply is one short json object, so the reasoning budget is waste
  /// (`reasoning_len` on the failure line still shows it if a gateway ignores
  /// the switch).
  static Map<String, dynamic> requestBody({
    required String model,
    required List<String> base64Jpegs,
    String? instruction,
    int maxTokens = firstMaxTokens,
  }) =>
      {
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': instruction ?? prompt},
              for (final jpeg in base64Jpegs)
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:image/jpeg;base64,$jpeg'},
                },
            ],
          },
        ],
        'temperature': 0,
        'max_tokens': maxTokens,
        // The prompt already asks for one JSON object; JSON mode is what stops
        // the reply being wrapped in prose or cut short mid-object.
        // Thinking mode is on by default with effort=high; this task only
        // needs a short json verdict, so that reasoning budget is pure waste
        // (api-docs.deepseek.com/guides/thinking_mode).
        'thinking': {'type': 'disabled'},
        'response_format': {'type': 'json_object'},
        'stream': false,
      };

  /// The per-image token ceiling from the DeepSeek vision docs
  /// (<https://api-docs.deepseek.com/>: 每张图最多 1024 token), so an estimate
  /// is clamped there instead of inventing a bigger bill than the API charges.
  static const int maxImageTokens = 1024;

  /// Rough number of input tokens one request costs, for the
  /// `[ai-marking] cand ... prompt_tok=` log field (docs/ai_marking.md
  /// §Logging). Only used when the reply carries no `usage` object.
  ///
  /// Diagnostics only — nothing is decided from it. A vision image costs about
  /// one token per 28×28 patch, so the dimensions in each JPEG's SOF header are
  /// a good enough stand-in for whatever `tile`/`crop` produced. Summed over
  /// every image in the request, each clamped to [maxImageTokens], the
  /// documented per-image cap.
  static int estimateInputTokens(List<Uint8List> jpegs, {String? instruction}) {
    if (jpegs.isEmpty) return 0;
    final text = (instruction ?? prompt).runes.length;
    var images = 0;
    for (final jpeg in jpegs) {
      final (width, height) = _jpegSize(jpeg);
      final visual = width == 0 || height == 0
          // No SOF header to read: a 896×1008 tile runs ~1.2k tokens, i.e. a
          // token per ~700 JPEG bytes.
          ? (jpeg.length / 700).ceil()
          : (width / 28).ceil() * (height / 28).ceil();
      images += math.min(visual, maxImageTokens);
    }
    return text + images + 32; // + the envelope, once per request
  }

  /// Pixel size from the first JPEG SOF marker, `(0, 0)` when there is none.
  static (int, int) _jpegSize(Uint8List bytes) {
    var at = 2; // past SOI
    while (at + 9 < bytes.length) {
      if (bytes[at] != 0xFF) {
        at++;
        continue;
      }
      final marker = bytes[at + 1];
      // Standalone markers carry no length field.
      if (marker == 0xD8 ||
          marker == 0x01 ||
          (marker >= 0xD0 && marker <= 0xD7)) {
        at += 2;
        continue;
      }
      final length = (bytes[at + 2] << 8) | bytes[at + 3];
      if (length < 2) break;
      final isStartOfFrame = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 && // DHT
          marker != 0xC8 && // JPG
          marker != 0xCC; // DAC
      if (isStartOfFrame) {
        final height = (bytes[at + 5] << 8) | bytes[at + 6];
        final width = (bytes[at + 7] << 8) | bytes[at + 8];
        return (width, height);
      }
      at += 2 + length;
    }
    return (0, 0);
  }

  /// Whether a 4xx body means "this model cannot take an image at all".
  ///
  /// Deliberately broad: a model without vision reports it as an unknown
  /// `image_url` variant, an unsupported content type, or an unknown modality,
  /// depending on the gateway in front of it.
  static bool looksLikeImageRejection(String body) => _imageHint.hasMatch(body);

  static final RegExp _imageHint = RegExp(
    r'image|vision|content[-_ ]?type|multimodal|modalit|不支持图片|图片输入',
    caseSensitive: false,
  );

  /// The `message.content` of one reply turned into the fixed JSON contract.
  ///
  /// Tolerates ```json fences, prose on either side and anything else around
  /// the first balanced `{...}`; only when there is no object in it at all is
  /// this a failed candidate.
  static AiJudgement parseContent(String content) {
    if (content.trim().isEmpty) {
      throw const AiMarkingException('empty message in reply');
    }
    final json = objectIn(content);
    final rawKind = json['kind'];
    final kind =
        rawKind is String && kinds.contains(rawKind) ? rawKind : 'other';
    final rawDescription = json['description'];
    return AiJudgement(
      highlight: json['highlight'] == true,
      kind: kind,
      description: rawDescription is String ? rawDescription.trim() : '',
    );
  }

  /// `content` as text: a string as-is, an array of parts joined from their
  /// `text` fields (vision gateways sometimes answer with parts), else empty.
  static String contentText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is String) {
          buffer.write(part);
        } else if (part is Map) {
          final text = part['text'];
          if (text is String) buffer.write(text);
        }
      }
      return buffer.toString();
    }
    return '';
  }

  /// The first balanced `{...}` block in [text], ignoring braces inside quoted
  /// strings. Null when no complete block exists (a body cut off mid-object).
  static String? firstJsonObject(String text) {
    for (var start = text.indexOf('{');
        start >= 0;
        start = text.indexOf('{', start + 1)) {
      var depth = 0;
      var inString = false;
      var escaped = false;
      for (var at = start; at < text.length; at++) {
        final char = text[at];
        if (inString) {
          if (escaped) {
            escaped = false;
          } else if (char == '\\') {
            escaped = true;
          } else if (char == '"') {
            inString = false;
          }
          continue;
        }
        if (char == '"') {
          inString = true;
        } else if (char == '{') {
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth == 0) return text.substring(start, at + 1);
        }
      }
    }
    return null;
  }

  /// [firstJsonObject] decoded; a failed candidate when there is none.
  static Map<String, dynamic> objectIn(String text) {
    final block = firstJsonObject(text);
    if (block == null) {
      throw const AiMarkingException('no JSON object in reply');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(block);
    } on FormatException {
      throw const AiMarkingException('malformed JSON in reply');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiMarkingException('reply JSON is not an object');
    }
    return decoded;
  }

  /// Collapse whitespace and cut to 300 characters for an error message.
  static String shorten(String body) {
    final flat = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= 300 ? flat : '${flat.substring(0, 300)}…';
  }

  /// POST the candidate's JPEGs (three views, see
  /// [AiMarkingService.tileFiltersFor]) and read the verdict, with exactly one
  /// retry.
  ///
  /// When the reply is cut short (`finish_reason=length`) or its `content` is
  /// empty — the shape a thinking model leaves behind once its budget is gone —
  /// the same segment is asked once more with [retryMaxTokens], and the retry
  /// carries the same images. A second failure is a failed candidate: there is
  /// never a third request. Serial by design otherwise: the caller awaits each
  /// candidate, which keeps us under the rate limit without backoff machinery.
  ///
  /// [onAttempt] observes every attempt for the log (finish_reason, usage,
  /// reasoning/content sizes). It cannot change the outcome and is never given
  /// the key or the body.
  Future<AiJudgement> judgeImage({
    required String apiKey,
    required String model,
    required List<Uint8List> jpegs,
    String? instruction,
    void Function(AiAttempt attempt)? onAttempt,
  }) async {
    final base64Jpegs = [for (final jpeg in jpegs) base64Encode(jpeg)];
    var attemptNo = 0;
    var maxTokens = firstMaxTokens;
    while (true) {
      attemptNo++;
      if (_cancelled) throw const AiCancelled();
      final (status, body) = await _post(
        apiKey: apiKey,
        model: model,
        base64Jpegs: base64Jpegs,
        instruction: instruction,
        maxTokens: maxTokens,
      );
      final reply = _Reply.tryParse(body);
      // Observation only: a throwing logger must not turn a good reply into a
      // failed candidate.
      try {
        onAttempt?.call(AiAttempt(
          attempt: attemptNo,
          status: status,
          maxTokens: maxTokens,
          finishReason: reply?.finishReason ?? '-',
          promptTokens: reply?.promptTokens,
          completionTokens: reply?.completionTokens,
          reasoningLen: reply?.reasoningLen ?? 0,
          contentLen: reply?.contentLen ?? 0,
        ));
      } catch (_) {}

      if (status == 401 || status == 403) {
        throw AiAuthFailure('HTTP $status: ${shorten(body)}');
      }
      if (status >= 400) {
        final detail = 'HTTP $status: ${shorten(body)}';
        if (status < 500 && looksLikeImageRejection(body)) {
          throw AiVisionUnsupported(detail);
        }
        throw AiMarkingException(detail);
      }
      if (reply == null) throw const AiMarkingException('reply is not JSON');

      final truncated = reply.finishReason == 'length';
      final empty = reply.content.trim().isEmpty;
      if (attemptNo == 1 && (truncated || empty)) {
        maxTokens = retryMaxTokens;
        continue;
      }
      if (empty) throw const AiMarkingException('empty message in reply');
      if (truncated) {
        throw const AiMarkingException(
            'reply truncated (finish_reason=length)');
      }
      return parseContent(reply.content);
    }
  }

  /// One request, `(status, body)`. Transport failures become
  /// [AiMarkingException]s and are not retried: the retry is for an answer the
  /// model cut short, not for a dead network.
  Future<(int, String)> _post({
    required String apiKey,
    required String model,
    required List<String> base64Jpegs,
    String? instruction,
    required int maxTokens,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _http = client;
    try {
      final request =
          await client.postUrl(Uri.parse(endpoint)).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $apiKey');
      request.headers.contentType = ContentType.json;
      request.add(utf8.encode(jsonEncode(requestBody(
        model: model,
        base64Jpegs: base64Jpegs,
        instruction: instruction,
        maxTokens: maxTokens,
      ))));

      final response = await request.close().timeout(timeout);
      final body =
          await response.transform(utf8.decoder).join().timeout(timeout);
      if (_cancelled) throw const AiCancelled();
      return (response.statusCode, body);
    } on TimeoutException {
      if (_cancelled) throw const AiCancelled();
      throw AiMarkingException('request timed out after ${timeout.inSeconds}s');
    } on SocketException catch (error) {
      if (_cancelled) throw const AiCancelled();
      throw AiMarkingException('network error: ${error.message}');
    } on HandshakeException catch (error) {
      if (_cancelled) throw const AiCancelled();
      throw AiMarkingException('TLS error: ${error.message}');
    } on HttpException catch (error) {
      if (_cancelled) throw const AiCancelled();
      throw AiMarkingException('HTTP client error: ${error.message}');
    } finally {
      _http = null;
      client.close(force: true);
    }
  }
}

/// A 200 body reduced to the four things the caller acts on; null when the body
/// is not a JSON object at all.
class _Reply {
  const _Reply({
    required this.content,
    required this.finishReason,
    required this.promptTokens,
    required this.completionTokens,
    required this.reasoningLen,
    required this.contentLen,
  });

  final String content;
  final String finishReason;
  final int? promptTokens;
  final int? completionTokens;
  final int reasoningLen;
  final int contentLen;

  static _Reply? tryParse(String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    final choices = decoded['choices'];
    final first = choices is List && choices.isNotEmpty ? choices.first : null;
    final message = first is Map ? first['message'] : null;
    final content = message is Map
        ? DeepSeekVisionClient.contentText(message['content'])
        : '';
    final reasoning = message is Map ? message['reasoning_content'] : null;
    final rawFinish = first is Map ? first['finish_reason'] : null;
    final usage = decoded['usage'];
    return _Reply(
      content: content,
      finishReason: rawFinish is String ? rawFinish : '-',
      promptTokens: usage is Map ? _int(usage['prompt_tokens']) : null,
      completionTokens: usage is Map ? _int(usage['completion_tokens']) : null,
      reasoningLen: reasoning is String ? reasoning.length : 0,
      contentLen: content.length,
    );
  }

  static int? _int(Object? value) => value is num ? value.toInt() : null;
}
