import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/data/project_file.dart';
import 'package:highlight_creator/data/settings_service.dart';
import 'package:highlight_creator/presentation/shell/goal_calibration_dialog.dart';
import 'package:highlight_creator/services/ai_marking_batch.dart';
import 'package:highlight_creator/services/ai_marking_service.dart';
import 'package:highlight_creator/services/audio_spike_detector.dart';
import 'package:highlight_creator/services/error_logger.dart';
import 'package:highlight_creator/services/goal_calibration.dart';
import 'package:highlight_creator/services/motion_spike_detector.dart';

/// One `[ai-marking]` line in the app's daily log — the same
/// `logs\error-YYYYMMDD.log` every other diagnostic goes to, never a second
/// log file. docs/ai_marking.md §Logging fixes the shape of each line.
void _aiLog(String message) {
  try {
    ErrorLogger.line('[ai-marking] $message');
  } catch (_) {
    // A broken log write must never take the analysis down with it.
  }
}

/// `1.8s`, the elapsed shape every line uses.
String _seconds(int milliseconds) =>
    '${(milliseconds / 1000).toStringAsFixed(1)}s';

/// `HH:MM:SS.mmm`, the `in=`/`out=` shape on a candidate line.
String _clockMs(int milliseconds) {
  String two(int value) => value.toString().padLeft(2, '0');
  final millis = (milliseconds % 1000).toString().padLeft(3, '0');
  return '${two(milliseconds ~/ 3600000)}:'
      '${two(milliseconds ~/ 60000 % 60)}:'
      '${two(milliseconds ~/ 1000 % 60)}.$millis';
}

/// One log-safe value: whitespace collapsed, cut to [max] characters.
String _clip(String text, int max) {
  final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= max ? flat : '${flat.substring(0, max)}…';
}

String _verdictName(AiVerdict verdict) => switch (verdict) {
      AiVerdict.highlight => 'highlight',
      AiVerdict.ordinary => 'ordinary',
      AiVerdict.unjudged => 'undetermined',
    };

/// The status code an `AiMarkingException` already carries as `HTTP 400: ...`.
int _statusIn(String message) {
  final match = RegExp(r'HTTP (\d{3})').firstMatch(message);
  return match == null ? 0 : int.parse(match.group(1)!);
}

/// How many candidates a channel produced, for the `src_*` log fields.
int _sourceCount(List<AiSegment> segments, AiCandidateSource source) =>
    segments.where((segment) => segment.source == source).length;

/// The single machine-parsable closing line of one file; field order is fixed
/// by docs/ai_marking.md §Logging. [prefix] is `file i/n ` for a batch run and
/// empty for a single-video one, so both formats stay greppable.
void _aiSummary({
  String prefix = '',
  required List<AiSegment> segments,
  required int failed,
  required int http,
  required String model,
  required int elapsedMs,
  required bool degraded,
  required int promptTokens,
  required int completionTokens,
  required int retried,
  required bool motionOk,
}) {
  final highlight =
      segments.where((s) => s.verdict == AiVerdict.highlight).length;
  final ordinary =
      segments.where((s) => s.verdict == AiVerdict.ordinary).length;
  final undetermined =
      segments.where((s) => s.verdict == AiVerdict.unjudged).length;
  // The eight fields below are fixed by docs/ai_marking.md §Logging; `ordinary`
  // and the three token counters are appended after them because the
  // implementation has a third verdict and otherwise highlight + undetermined +
  // failed would not add up. `src_*` / `motion_ok` come last: they are the
  // evidence the motion-channel experiment is judged on.
  _aiLog('${prefix}summary candidates=${segments.length} highlight=$highlight'
      ' undetermined=$undetermined failed=$failed'
      ' http=${http == 0 ? '-' : http} model=$model'
      ' elapsed=${(elapsedMs / 1000).round()}s degraded=$degraded'
      ' ordinary=$ordinary'
      ' prompt_tok=$promptTokens completion_tok=$completionTokens'
      ' retried=$retried'
      ' src_both=${_sourceCount(segments, AiCandidateSource.both)}'
      ' src_motion=${_sourceCount(segments, AiCandidateSource.motion)}'
      ' src_audio=${_sourceCount(segments, AiCandidateSource.audio)}'
      ' motion_ok=$motionOk');
}

/// What a running file reports upward while it runs: the stage line under the
/// bar, the fraction of **this** file (0..1), and how many candidates the whole
/// batch has produced so far.
typedef _Update = void Function({
  String? stage,
  double? progress,
  int? candidates,
});

/// What one file adds to the batch totals.
class _FileOutcome {
  int failed = 0;
  int promptTokens = 0;

  /// 401 or "this model has no vision", or 取消: every later file would fail
  /// the same way (or the user asked to stop), so the batch stops here.
  bool stopBatch = false;
}

/// One line of the two grouped lists — a file header, a segment, or a note.
abstract class _Row {
  const _Row();
}

class _GroupRow extends _Row {
  const _GroupRow(this.title, this.trailing);

  final String title;
  final String trailing;
}

class _NoteRow extends _Row {
  const _NoteRow(this.text);

  final String text;
}

class _SegmentRow extends _Row {
  const _SegmentRow({
    required this.path,
    required this.segment,
    required this.kindLabel,
    required this.highlightOnly,
  });

  /// The file this segment belongs to: the preview must open **this** path,
  /// never the first file of the batch.
  final String path;
  final AiSegment segment;
  final String kindLabel;

  /// True in the 「高光片段」 list (click to play, no verdict chip), false in
  /// the candidate list (verdict chip + 查看 button).
  final bool highlightOnly;
}

/// 「我要 → AI 打点」: one or more match videos in, one `.hlcproj` of likely
/// highlights out. See docs/ai_marking.md for the flow, the heuristic and the
/// failure modes; this file is only the dialog around it.
Future<void> openAiMarkingDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    // Modal on purpose: a run costs API calls and can take minutes, so a stray
    // click next to the dialog must not throw the result away. The only exits
    // are the dialog's own 关闭 (which cancels the run) and 取消.
    barrierDismissible: false,
    builder: (_) => const AiMarkingDialog(),
  );
}

class AiMarkingDialog extends ConsumerStatefulWidget {
  const AiMarkingDialog({super.key});

  static Future<void> show(BuildContext context) =>
      openAiMarkingDialog(context);

  @override
  ConsumerState<AiMarkingDialog> createState() => _AiMarkingDialogState();
}

class _AiMarkingDialogState extends ConsumerState<AiMarkingDialog> {
  /// The formats the picker offers and the only ones accepted afterwards.
  static const List<String> _videoExtensions = ['mp4', 'mov', 'mkv'];

  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _modelController =
      TextEditingController(text: DeepSeekVisionClient.defaultModel);

  bool _remember = false;
  bool _obscureKey = true;

  /// The selected files in run order (file name, see [sortBatchFiles]).
  List<String> _paths = const <String>[];

  /// Lengths probed at pick time, so 「共 X 分钟」 is right before a run and the
  /// start line does not pay for a second ffprobe.
  final Map<String, int> _durations = <String, int>{};

  /// One entry per selected file, in run order; `segments` fills in as each
  /// file is analysed and stays on screen for the whole batch.
  List<AiFileResult> _results = <AiFileResult>[];

  String? _stageText;

  /// File-level line above the bar: 「第 2/11 个文件 · 已完成候选 47 段」.
  String? _fileText;
  String? _banner;
  String? _error;
  String? _savedPath;
  String? _calibrationNotice;
  double _progress = 0;
  bool _running = false;

  /// Candidates that failed to judge, across the whole batch.
  int _failed = 0;

  /// Files given up on (skipped), across the whole batch.
  int _skippedFiles = 0;

  /// Bumped on every run so a superseded run cannot write into the new one.
  int _runId = 0;

  AiMarkingService? _service;
  DeepSeekVisionClient? _client;

  AppStrings get _l10n => ref.read(l10nProvider);

  /// Every candidate of every file, for the batch-wide counters.
  Iterable<AiSegment> get _segments sync* {
    for (final result in _results) {
      yield* result.segments;
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedKey());
  }

  @override
  void dispose() {
    _service?.cancel();
    _client?.cancel();
    _keyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  /// The key is only there if the user ticked 记住 last time.
  Future<void> _loadSavedKey() async {
    final saved = await ref.read(settingsServiceProvider).aiMarkingApiKey;
    if (!mounted || saved.isEmpty) return;
    setState(() {
      _keyController.text = saved;
      _remember = true;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _error = message);
  }

  static String _extensionOf(String path) {
    final name = fileNameOf(path);
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static String _baseNameOf(String path) {
    final name = fileNameOf(path);
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// 「共 X 分钟」 for the picker summary; `—` when nothing could be probed.
  String get _minutesText {
    final total =
        _paths.fold<int>(0, (sum, path) => sum + (_durations[path] ?? 0));
    return total <= 0 ? '—' : (total / 60000).toStringAsFixed(1);
  }

  Future<void> _pickVideos() async {
    final l10n = _l10n;
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: l10n.aiPickVideo,
        type: FileType.custom,
        allowedExtensions: _videoExtensions,
        allowMultiple: true,
      );
      final chosen = <String>[
        for (final file in picked?.files ?? const <PlatformFile>[])
          if (file.path != null && file.path!.isNotEmpty) file.path!,
      ];
      if (chosen.isEmpty) return;
      final supported = [
        for (final path in chosen)
          if (_videoExtensions.contains(_extensionOf(path))) path,
      ];
      if (supported.isEmpty) {
        _showError(l10n.aiUnsupportedFormat);
        return;
      }
      final paths = sortBatchFiles(supported);
      setState(() {
        _paths = paths;
        _results = <AiFileResult>[];
        _savedPath = null;
        _banner = null;
        _error = null;
        _calibrationNotice = null;
        _failed = 0;
        _skippedFiles = 0;
        _progress = 0;
        _stageText = null;
        _fileText = null;
      });
      unawaited(_probeDurations(paths));
    } catch (error) {
      _showError(l10n.aiAnalysisFailed(error));
    }
  }

  /// One ffprobe per selected file, cached: the picker summary needs the total
  /// length, and every start line needs its own file's length.
  Future<void> _probeDurations(List<String> paths) async {
    for (final path in paths) {
      if (!mounted || _running) return;
      if ((_durations[path] ?? 0) > 0) continue;
      final ms = await VideoProcessingService.probeDurationMs(path) ?? 0;
      if (!mounted) return;
      setState(() => _durations[path] = ms);
    }
  }

  Future<int> _durationFor(String path) async {
    final cached = _durations[path] ?? 0;
    if (cached > 0) return cached;
    final ms = await VideoProcessingService.probeDurationMs(path) ?? 0;
    _durations[path] = ms;
    return ms;
  }

  /// 「标定球门」: draw the two goal boxes on a frame of the **first** selected
  /// file; the result is read back at the start of each file's analysis
  /// (docs/ai_marking.md §球门标定).
  Future<void> _calibrateGoal() async {
    if (_paths.isEmpty) {
      _showError(_l10n.aiNeedFile);
      return;
    }
    final count =
        await openGoalCalibrationDialog(context, sourcePath: _paths.first);
    if (!mounted || count == null) return;
    setState(() => _calibrationNotice = _l10n.goalCalibSaved(count));
  }

  /// One camera for the whole batch: a calibration on any selected file is the
  /// calibration for all of them (docs/ai_marking.md §球门标定). Only runs when
  /// at least one file has boxes and at least one does not, so a per-file
  /// calibration is never thrown away for nothing.
  ///
  /// ponytail: `applyToSiblings` writes every video in the folder, so if two
  /// selected files carry *different* boxes the later write wins. Same-camera
  /// batches are the confirmed use; anything else needs a per-file prompt.
  int _applyBatchCalibration(List<String> paths) {
    final missing = <String>[];
    String? calibrated;
    var boxes = 0;
    for (final path in paths) {
      final calibration = GoalCalibration.load(path);
      if (calibration == null) {
        missing.add(path);
      } else if (calibrated == null) {
        calibrated = path;
        boxes = calibration.rects.length;
      }
    }
    if (calibrated == null || missing.isEmpty) return 0;
    final written = GoalCalibration.applyToSiblings(calibrated);
    if (written <= 0) return 0;
    _aiLog('calib applied from=${fileNameOf(calibrated)}'
        ' files=$written boxes=$boxes');
    return written;
  }

  /// The batch: every selected file, one at a time, in file-name order.
  ///
  /// A file's failure is recorded and the loop moves on; 401 / "no vision" stop
  /// it because every remaining request would fail identically; 取消 kills the
  /// running ffmpeg and closes the in-flight HTTP, then the loop notices and
  /// stops. Every exit path leaves `_running == false` and nothing under
  /// `temp\ai_marking` behind, and leaves `[ai-marking] ...` traces in
  /// `logs\error-YYYYMMDD.log` (docs/ai_marking.md §Logging).
  Future<void> _analyze() async {
    if (_running) return;
    final l10n = _l10n;
    final paths = sortBatchFiles(_paths);
    if (paths.isEmpty) {
      _showError(l10n.aiNeedFile);
      return;
    }
    final apiKey = _keyController.text.trim();
    if (apiKey.isEmpty) {
      _showError(l10n.aiNeedKey);
      return;
    }
    final model = _modelController.text.trim().isEmpty
        ? DeepSeekVisionClient.defaultModel
        : _modelController.text.trim();

    // 记住: write back only when ticked; unticking forgets a previously saved
    // key, which is what "remember" means to the next launch.
    unawaited(
      ref
          .read(settingsServiceProvider)
          .setAiMarkingApiKey(_remember ? apiKey : ''),
    );

    final ffmpeg = await VideoProcessingService.findFfmpeg();
    if (!mounted) return;
    if (ffmpeg == null) {
      _showError(l10n.aiNoFfmpeg);
      return;
    }

    final runId = ++_runId;
    final service = AiMarkingService(ffmpegPath: ffmpeg);
    final client = DeepSeekVisionClient();
    _service = service;
    _client = client;

    final batchClock = Stopwatch()..start();
    final results = [for (final path in paths) AiFileResult(path: path)];
    var promptTokensTotal = 0;
    var failed = 0;
    var skipped = 0;
    var ok = 0;
    var cancelled = false;
    var completedCandidates = 0;

    setState(() {
      _running = true;
      _paths = paths;
      _results = results;
      _failed = 0;
      _skippedFiles = 0;
      _banner = null;
      _error = null;
      _savedPath = null;
      _calibrationNotice = null;
      _progress = 0;
      _stageText = l10n.aiStageAudio;
      _fileText =
          paths.length > 1 ? l10n.aiBatchProgress(1, paths.length, 0) : null;
    });

    // 「batch ... started」 first, then the one-camera calibration: the calib
    // write has to be in place before the first start line reads it, so every
    // file logs its own calib=.
    _aiLog('batch files=${paths.length} started');
    final applied = _applyBatchCalibration(paths);
    if (!mounted) return;
    if (runId != _runId) return;
    if (applied > 0) {
      setState(() => _calibrationNotice = l10n.aiCalibAppliedToBatch(applied));
    }

    for (var index = 0; index < paths.length; index++) {
      // A newer run took over (重新分析): stop quietly, the batch line below
      // still closes this one.
      if (runId != _runId) break;
      if (service.isCancelled || client.isCancelled) {
        cancelled = true;
        break;
      }
      final result = results[index];
      final fileClock = Stopwatch()..start();

      void update({String? stage, double? progress, int? candidates}) {
        if (!mounted || runId != _runId) return;
        final fraction = progress;
        final count = candidates;
        final text = stage;
        if (fraction != null) {
          _progress = (index + fraction.clamp(0.0, 1.0)) / paths.length;
        }
        setState(() {
          if (count != null) completedCandidates = count;
          if (text != null) _stageText = text;
          if (paths.length > 1) {
            _fileText = l10n.aiBatchProgress(
              index + 1,
              paths.length,
              completedCandidates,
            );
          }
        });
      }

      update(stage: l10n.aiStageAudio, progress: 0.02);
      try {
        final outcome = await _runFile(
          result: result,
          index: index,
          total: paths.length,
          candidatesBefore: completedCandidates,
          runId: runId,
          service: service,
          client: client,
          apiKey: apiKey,
          model: model,
          update: update,
        );
        ok++;
        failed += outcome.failed;
        promptTokensTotal += outcome.promptTokens;
        // 取消 stops the whole batch, and so does 401 / "no vision": every
        // remaining request would fail identically.
        if (service.isCancelled || client.isCancelled) {
          cancelled = true;
          break;
        }
        if (outcome.stopBatch) break;
      } on AiCancelled {
        cancelled = true;
        break;
      } catch (error) {
        // One unreadable file must not take the batch down: record it as
        // 跳过, keep whatever the other files produced, and move on.
        skipped++;
        result.skipped = true;
        result.error = '$error';
        fileClock.stop();
        if (paths.length > 1) {
          _aiLog('${fileLogPrefix(index, paths.length)}skipped'
              ' file=${result.fileName}'
              ' elapsed=${_seconds(fileClock.elapsedMilliseconds)}'
              ' error=${_clip('$error', 200)}');
        }
        if (mounted && runId == _runId) {
          setState(() => _skippedFiles = skipped);
        }
      }
    }

    batchClock.stop();
    _aiLog(batchDoneLine(
      files: paths.length,
      ok: ok,
      skipped: skipped,
      highlightTotal: totalHighlights(results),
      promptTokens: promptTokensTotal,
      elapsedMs: batchClock.elapsedMilliseconds,
    ));

    if (mounted && runId == _runId) {
      setState(() {
        _running = false;
        _failed = failed;
        _skippedFiles = skipped;
        if (!cancelled && _error == null && _banner == null) {
          _progress = 1;
          _stageText = l10n.aiStageDone;
        }
        if (cancelled) _stageText = l10n.aiCancelled;
        // `_fileText` is deliberately left at the file that actually ran: on
        // 取消/401 it must not claim the last file of the selection.
      });
    }
    if (_service == service) _service = null;
    if (_client == client) _client = null;
  }

  /// A → B → C for **one** file, serial, with the batch totals kept by
  /// [_analyze]. Every early exit leaves the outcome populated; a throw means
  /// this file is skipped (except [AiCancelled], which stops the batch).
  Future<_FileOutcome> _runFile({
    required AiFileResult result,
    required int index,
    required int total,
    required int candidatesBefore,
    required int runId,
    required AiMarkingService service,
    required DeepSeekVisionClient client,
    required String apiKey,
    required String model,
    required _Update update,
  }) async {
    final l10n = _l10n;
    final source = result.path;
    final prefix = fileLogPrefix(index, total);
    final outcome = _FileOutcome();
    final startedAt = DateTime.now();
    // Probed once per file, up front: the start line needs the length, and step
    // B reuses it for the edge clipping instead of paying for a second ffprobe.
    final durationMs = await _durationFor(source);
    if (!mounted || runId != _runId) throw const AiCancelled();
    result.durationMs = durationMs;
    // 球门标定: each file is read by its own sha1 — the batch head may have just
    // written this file's boxes from a sibling (§球门标定).
    final calibration = GoalCalibration.load(source);
    final goalCount = calibration?.rects.length ?? 0;
    // Same images, different wording: goal-region zooms when calibrated.
    final instruction = DeepSeekVisionClient.promptFor(goals: goalCount);
    // The log gets the file name only: the folder adds nothing a replay needs.
    _aiLog('${prefix}start file=${result.fileName}'
        ' duration=${durationMs > 0 ? _seconds(durationMs) : '-'}'
        ' model=$model baseUrl=${client.endpoint} calib=$goalCount'
        '${total > 1 ? ' candidates_before=$candidatesBefore' : ''}');

    var cancelled = false;
    var failed = 0;
    var stopped = false;
    var degraded = false;
    var motionOk = true;
    var lastHttp = 0;
    var attempted = 0;
    var cancelledLogged = false;
    // Every attempt is an input charge, the retry included.
    var promptTokensTotal = 0;
    var completionTokensTotal = 0;
    var retried = 0;
    final segments = <AiSegment>[];
    result.segments = segments;
    File? wav;

    try {
      // A. audio — the assistant channel.
      final audioClock = Stopwatch()..start();
      wav = await service.extractAudio(source);
      audioClock.stop();
      var wavBytes = -1;
      try {
        wavBytes = wav.lengthSync();
      } catch (_) {}
      _aiLog('audio elapsed=${_seconds(audioClock.elapsedMilliseconds)}'
          ' size=${wavBytes < 0 ? '-' : '${wavBytes}B'}');

      // A2. 画面运动 — the primary channel. A failure here (no ffmpeg filter,
      // unparsable metadata, a broken file) must never take the analysis down:
      // log it, tell the user, and carry on with sound only.
      update(stage: l10n.aiStageMotion, progress: 0.06);
      final motionClock = Stopwatch()..start();
      var motionFrames = const <double>[];
      try {
        final metadata = await service.extractMotion(source);
        try {
          motionFrames =
              MotionSpikeDetector.parseFrames(await metadata.readAsString());
        } finally {
          AiMarkingService.deleteQuietly(metadata);
        }
        if (motionFrames.length < MotionSpikeDetector.fps * 2) {
          throw AiMarkingException(
              'motion metadata holds ${motionFrames.length} frames');
        }
      } on AiCancelled {
        rethrow;
      } catch (error) {
        motionOk = false;
        motionFrames = const <double>[];
        _aiLog('motion unavailable'
            ' elapsed=${_seconds(motionClock.elapsedMilliseconds)}'
            ' error=${_clip('$error', 200)}');
        if (mounted && runId == _runId) {
          setState(() => _banner = l10n.aiMotionUnavailable);
        }
      }

      // B. candidates: run both channels, take their union.
      update(stage: l10n.aiStageDetect, progress: 0.12);
      final detectClock = Stopwatch()..start();
      AudioDetectStats? stats;
      final audioCandidates = AudioSpikeDetector.detect(
        await wav.readAsBytes(),
        durationMs: durationMs > 0 ? durationMs : null,
        onStats: (value) => stats = value,
      );
      MotionDetectStats? motionStats;
      final motionCandidates = motionFrames.isEmpty
          ? const <MotionCandidate>[]
          : MotionSpikeDetector.detect(
              motionFrames,
              durationMs: durationMs > 0 ? durationMs : null,
              onStats: (value) => motionStats = value,
            );
      motionClock.stop();
      final motion = motionStats;
      if (motion != null) {
        _aiLog('motion frames=${motion.frames}'
            ' elapsed=${_seconds(motionClock.elapsedMilliseconds)}'
            ' mean=${motion.mean.toStringAsFixed(2)}'
            ' p95=${motion.p95.toStringAsFixed(2)}'
            ' candidates=${motionCandidates.length}');
      }
      segments.addAll(mergeCandidateChannels(
        audio: audioCandidates,
        motion: motionCandidates,
      ));
      detectClock.stop();
      final used = stats;
      final thresholds = used == null
          ? 'median=- energyFactor=- whistleFactor=- zcrFactor=-'
              ' baselineWindowSec=- relaxed=-'
          : 'median=${used.median.toStringAsFixed(6)}'
              ' energyFactor=${used.energyFactor.toStringAsFixed(1)}'
              ' whistleFactor=${used.whistleFactor.toStringAsFixed(1)}'
              ' zcrFactor=${used.zcrFactor.toStringAsFixed(1)}'
              ' baselineWindowSec=${used.baselineWindowSec}'
              ' relaxed=${used.relaxed}';
      _aiLog('detect audio=${audioCandidates.length}'
          ' motion=${motionCandidates.length}'
          ' merged=${segments.length}'
          ' src_both=${_sourceCount(segments, AiCandidateSource.both)}'
          ' src_motion=${_sourceCount(segments, AiCandidateSource.motion)}'
          ' src_audio=${_sourceCount(segments, AiCandidateSource.audio)}'
          ' win=peak-${AudioSpikeDetector.leadMs ~/ 1000}s..'
          'peak+${AudioSpikeDetector.tailMs ~/ 1000}s'
          ' elapsed=${_seconds(detectClock.elapsedMilliseconds)}'
          ' $thresholds');

      if (!mounted || runId != _runId) throw const AiCancelled();
      update(
        stage: segments.isEmpty ? l10n.aiStageDone : l10n.aiStageJudge,
        progress: segments.isEmpty ? 1 : 0.2,
        candidates: candidatesBefore + segments.length,
      );
      if (segments.isEmpty) return outcome;

      // C. one candidate at a time: a rate limit, a 401 or "no images" must
      // stop everything, while a single bad reply must stop nothing.
      for (var i = 0; i < segments.length; i++) {
        if (runId != _runId) throw const AiCancelled();
        if (service.isCancelled || client.isCancelled) {
          cancelled = true;
          break;
        }
        attempted = i + 1;
        update(
          stage: '${l10n.aiStageJudge} ${i + 1}/${segments.length}',
          progress: 0.2 + 0.8 * i / segments.length,
        );
        final segment = segments[i];
        final judgeClock = Stopwatch()..start();
        // The three views of this candidate; emptied again in `finally`.
        var tiles = const <File>[];
        var http = 0;
        var estimatedTokens = 0;
        int? promptTokens;
        int? completionTokens;
        var finishReason = '-';
        var reasoningLen = 0;
        var contentLen = 0;
        var attempts = 0;
        var failure = '';
        try {
          tiles = await service.captureTiles(
            sourcePath: source,
            segment: segment,
            tag: '$i',
            calibration: calibration,
          );
          final jpegs = [for (final tile in tiles) await tile.readAsBytes()];
          estimatedTokens = DeepSeekVisionClient.estimateInputTokens(jpegs,
              instruction: instruction);
          final judgement = await client.judgeImage(
            apiKey: apiKey,
            model: model,
            jpegs: jpegs,
            instruction: instruction,
            onAttempt: (attempt) {
              http = attempt.status;
              lastHttp = attempt.status;
              finishReason = attempt.finishReason;
              promptTokens = attempt.promptTokens;
              completionTokens = attempt.completionTokens;
              reasoningLen = attempt.reasoningLen;
              contentLen = attempt.contentLen;
              attempts = attempt.attempt;
              promptTokensTotal += attempt.promptTokens ?? estimatedTokens;
              completionTokensTotal += attempt.completionTokens ?? 0;
              if (attempt.retried) retried++;
            },
          );
          if (!mounted || runId != _runId) throw const AiCancelled();
          segment.verdict =
              judgement.highlight ? AiVerdict.highlight : AiVerdict.ordinary;
          segment.kind = judgement.kind;
          segment.description = judgement.description;
          segment.error = null;
        } on AiVisionUnsupported catch (error) {
          // D. This model has no vision input. Every remaining request would
          // fail identically, so keep the candidates and stop asking.
          for (final candidate in segments) {
            candidate.verdict = AiVerdict.unjudged;
          }
          degraded = true;
          final status = http != 0 ? http : _statusIn('$error');
          _aiLog('degraded reason=image-unsupported'
              ' status=${status == 0 ? '-' : status}'
              ' firstError=${_clip('$error', 200)}');
          if (mounted && runId == _runId) {
            setState(() => _banner = l10n.aiUnsupportedBanner);
          }
          stopped = true;
        } on AiAuthFailure catch (error) {
          for (final candidate in segments) {
            candidate.verdict = AiVerdict.unjudged;
          }
          _aiLog('error stage=auth http=${http == 0 ? '-' : http}'
              ' error=${_clip('$error', 200)}');
          if (mounted && runId == _runId) {
            setState(() => _error = l10n.aiInvalidKey);
          }
          stopped = true;
        } on AiCancelled {
          cancelled = true;
        } catch (error) {
          failed++;
          segment.verdict = AiVerdict.unjudged;
          segment.error = '$error';
          failure = '$error';
        } finally {
          for (final tile in tiles) {
            AiMarkingService.deleteQuietly(tile);
          }
        }
        judgeClock.stop();

        if (cancelled) {
          _aiLog('cancelled at=$attempted/${segments.length}');
          cancelledLogged = true;
          break;
        }
        final verdict =
            failure.isEmpty ? _verdictName(segment.verdict) : 'failed';
        // Real usage when the reply carried it, an estimate (marked `~`) when
        // it did not, `-` when no request went out at all (frame capture).
        final String tokenField;
        if (attempts == 0) {
          tokenField = '-';
        } else if (promptTokens != null) {
          tokenField = '$promptTokens';
        } else {
          tokenField = '~$estimatedTokens';
        }
        final retryField = attempts > 1 ? ' attempts=$attempts' : '';
        _aiLog('cand $attempted/${segments.length}'
            ' in=${_clockMs(segment.startMs)}'
            ' out=${_clockMs(segment.endMs)}'
            // start relative to the peak: -6000 means peak - 6 s (see the
            // detect line for the full peak-6s..peak+2s shape).
            ' win=${segment.startMs - segment.peakMs}'
            ' src=${segment.source.name}'
            ' http=${http == 0 ? '-' : http}'
            ' verdict=$verdict'
            ' kind=${segment.kind}'
            ' imgs=${tiles.length}'
            ' ${_seconds(judgeClock.elapsedMilliseconds)}'
            ' prompt_tok=$tokenField$retryField'
            ' desc=${segment.description.isEmpty ? '-' : _clip(segment.description, 60)}');
        if (failure.isNotEmpty) {
          // Never the body itself: the shape of the answer is what diagnoses
          // "empty content" / "truncated JSON" (docs/ai_marking.md §Logging).
          _aiLog('error cand=$attempted/${segments.length}'
              ' http=${http == 0 ? '-' : http}'
              ' elapsed=${_seconds(judgeClock.elapsedMilliseconds)}'
              ' finish_reason=$finishReason'
              ' usage.prompt_tokens=${promptTokens ?? '-'}'
              ' usage.completion_tokens=${completionTokens ?? '-'}'
              ' reasoning_len=$reasoningLen'
              ' content_len=$contentLen'
              ' error=${_clip(failure, 200)}');
        }
        if (mounted && runId == _runId) setState(() {});
        if (stopped) break;
      }

      if (cancelled) {
        update(stage: l10n.aiCancelled);
      } else if (!stopped) {
        update(stage: l10n.aiStageDone, progress: 1);
      }
      outcome.stopBatch = stopped;
      return outcome;
    } on AiCancelled {
      // The dialog went away or a newer run took over: nothing to log here.
      cancelled = true;
      outcome.stopBatch = true;
      rethrow;
    } catch (error) {
      _aiLog('error stage=run http=- error=${_clip('$error', 200)}');
      rethrow;
    } finally {
      if (cancelled && !cancelledLogged) {
        _aiLog('cancelled at=$attempted/${segments.length}');
      }
      _aiSummary(
        prefix: prefix,
        segments: segments,
        failed: failed,
        http: lastHttp,
        model: model,
        elapsedMs: DateTime.now().difference(startedAt).inMilliseconds,
        degraded: degraded,
        promptTokens: promptTokensTotal,
        completionTokens: completionTokensTotal,
        retried: retried,
        motionOk: motionOk,
      );
      outcome
        ..failed = failed
        ..promptTokens = promptTokensTotal
        ..stopBatch = outcome.stopBatch || cancelled;
      // The WAV is per file: deleting it here is what keeps a batch from
      // piling up `temp\ai_marking` (docs/ai_marking.md §F).
      if (wav != null) AiMarkingService.deleteQuietly(wav);
    }
  }

  void _cancel() {
    _service?.cancel();
    _client?.cancel();
    setState(() {
      _stageText = _l10n.aiCancelled;
      _running = false;
    });
  }

  /// E. Write every file's candidates worth keeping as **one** `.hlcproj`
  /// (docs/hlcproj_format.md): one `sources[]` entry per analysed file and
  /// every `timeslots[].videoSourceId` pointing at its own file. A healthy run
  /// writes only the highlights; a run the model could not judge writes its
  /// candidates too, with rating 2. "普通" is the only verdict that never
  /// reaches the file.
  Future<void> _saveProject() async {
    final l10n = _l10n;
    final finished = [
      for (final result in _results)
        if (!result.skipped) result,
    ];
    if (!finished.any((result) => result.segments
        .any((segment) => segment.verdict != AiVerdict.ordinary))) {
      _showError(l10n.aiNoHighlight);
      return;
    }

    // Fill in what only the writer needs: the real length (when ffprobe gave
    // one at pick time it is already here) and the frame size.
    for (final result in finished) {
      if (result.durationMs <= 0) {
        result.durationMs = await _durationFor(result.path);
      }
      final resolution =
          await VideoProcessingService.probeResolution(result.path);
      result.width = resolution?.$1 ?? 0;
      result.height = resolution?.$2 ?? 0;
      if (!mounted) return;
    }

    // The batch is named after its first file: one sorted batch belongs to one
    // match, and that file's name carries the date the project needs.
    final first = finished.first;
    final baseName = _baseNameOf(first.path);
    final date = projectDateFromFileName(first.path) ?? DateTime.now();
    final json = buildAiProjectJson(
      files: _results,
      name: baseName,
      date: projectDateValue(date),
      describe: (index, segment) => segment.description.isEmpty
          ? l10n.aiCandidateFallback(index)
          : segment.description,
    );

    try {
      final directory =
          Directory('${AppPaths.resultsDir}${Platform.pathSeparator}ai_marking')
            ..createSync(recursive: true);
      final stamp = _stamp(DateTime.now());
      final file = File('${directory.path}${Platform.pathSeparator}'
          '$baseName-${projectDateValue(date)}-$stamp.hlcproj');
      await file
          .writeAsString(const JsonEncoder.withIndent('  ').convert(json));
      if (!mounted) return;
      setState(() {
        _savedPath = file.path;
        _error = null;
      });
    } catch (error) {
      _showError(l10n.aiSaveFailed(error));
    }
  }

  Future<void> _openPreview(String path, AiSegment segment) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SegmentPreviewDialog(
        title: '${_clock(segment.startMs)}–${_clock(segment.endMs)}',
        closeLabel: _l10n.close,
        filePath: path,
        startMs: segment.startMs,
        endMs: segment.endMs,
      ),
    );
  }

  static String _clock(int ms) {
    final totalSeconds = ms ~/ 1000;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  static String _stamp(DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(now.hour)}${two(now.minute)}${two(now.second)}';
  }

  /// The 「高光片段」 list: one group per selected file, in batch order, each
  /// with its `highlight` rows — and a note when a file had none or was
  /// skipped, so a file that ran never silently disappears.
  List<_Row> _highlightRows(AppStrings l10n) {
    final rows = <_Row>[];
    for (final group in highlightGroups(_results)) {
      rows.add(
          _GroupRow(group.fileName, l10n.aiFileHighlightCount(group.count)));
      if (group.skipped) {
        rows.add(_NoteRow(l10n.aiFileSkipped));
        continue;
      }
      if (group.segments.isEmpty) {
        rows.add(_NoteRow(l10n.aiNoFileHighlights));
        continue;
      }
      for (final segment in group.segments) {
        rows.add(_SegmentRow(
          path: group.path,
          segment: segment,
          kindLabel: l10n.aiKindLabel(segment.kind),
          highlightOnly: true,
        ));
      }
    }
    return rows;
  }

  /// The existing candidate list, now grouped by file: every candidate of every
  /// file stays there, whatever the model said about it.
  List<_Row> _candidateRows(AppStrings l10n) {
    final rows = <_Row>[];
    for (final result in _results) {
      rows.add(_GroupRow(
        result.fileName,
        l10n.aiFileCandidateCount(result.segments.length),
      ));
      if (result.skipped) {
        rows.add(_NoteRow(l10n.aiFileSkipped));
        continue;
      }
      for (final segment in result.segments) {
        rows.add(_SegmentRow(
          path: result.path,
          segment: segment,
          kindLabel: l10n.aiKindLabel(segment.kind),
          highlightOnly: false,
        ));
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final theme = Theme.of(context);
    final highlights = _highlightRows(l10n);
    final candidates = _candidateRows(l10n);
    final canSave = !_running &&
        _segments.any((segment) => segment.verdict != AiVerdict.ordinary);
    final hasResults = _results.isNotEmpty;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.auto_awesome_outlined, size: 20),
          const SizedBox(width: 8),
          Text(l10n.aiTitle),
        ],
      ),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // D. The "no images" fallback has to be impossible to miss.
              if (_banner != null) _notice(theme, _banner!, warning: true),
              if (_error != null) _notice(theme, _error!, warning: false),
              const SizedBox(height: 6),
              TextField(
                controller: _modelController,
                enabled: !_running,
                decoration: InputDecoration(
                  labelText: l10n.aiModel,
                  helperText: DeepSeekVisionClient.knownModels.join(' / '),
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _keyController,
                enabled: !_running,
                obscureText: _obscureKey,
                decoration: InputDecoration(
                  labelText: l10n.aiApiKey,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _obscureKey ? l10n.aiShowKey : l10n.aiHideKey,
                    icon: Icon(
                      _obscureKey ? Icons.visibility_off : Icons.visibility,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _obscureKey = !_obscureKey),
                  ),
                ),
              ),
              Row(
                children: [
                  Checkbox(
                    key: const Key('ai_remember_key'),
                    value: _remember,
                    onChanged: _running
                        ? null
                        : (value) => setState(() => _remember = value ?? false),
                  ),
                  Text(l10n.aiRememberKey, style: theme.textTheme.bodySmall),
                  const Spacer(),
                  TextButton.icon(
                    key: const Key('ai_calibrate_goal'),
                    onPressed:
                        _running || _paths.isEmpty ? null : _calibrateGoal,
                    icon: const Icon(Icons.crop_free, size: 16),
                    label: Text(l10n.aiCalibrateGoal),
                  ),
                  TextButton.icon(
                    key: const Key('ai_pick_video'),
                    onPressed: _running ? null : _pickVideos,
                    icon: const Icon(Icons.video_file_outlined, size: 16),
                    label: Text(l10n.aiPickVideo),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.movie_outlined, size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Tooltip(
                      // The names are a tooltip because eleven of them do not
                      // fit on one line.
                      message:
                          _paths.isEmpty ? l10n.aiNoFile : _paths.join('\n'),
                      child: Text(
                        _paths.isEmpty
                            ? l10n.aiNoFile
                            : l10n.aiPickedFiles(_paths.length, _minutesText),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                  Text(l10n.aiSupportedFormats,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
              if (_calibrationNotice != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.greenAccent),
                    const SizedBox(width: 6),
                    Text(
                      _calibrationNotice!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: Colors.greenAccent),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (!hasResults)
                    FilledButton.icon(
                      key: const Key('ai_start'),
                      onPressed: _running || _paths.isEmpty ? null : _analyze,
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(l10n.aiStart),
                    ),
                  if (!hasResults) const SizedBox(width: 8),
                  if (_running)
                    OutlinedButton(
                      key: const Key('ai_cancel'),
                      onPressed: _cancel,
                      child: Text(l10n.cancel),
                    ),
                ],
              ),
              if (_stageText != null || _running) ...[
                const SizedBox(height: 10),
                // File level first: in a batch the bar alone cannot say whether
                // the run is at file 2 or file 9.
                if (_fileText != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.queue_music, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _fileText!,
                            key: const Key('ai_batch_progress'),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                LinearProgressIndicator(
                  value: _progress.clamp(0.0, 1.0),
                  minHeight: 6,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(_stageText ?? '',
                          style: theme.textTheme.bodySmall),
                    ),
                    if (_failed > 0)
                      Text(l10n.aiFailedCount(_failed),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.orangeAccent)),
                    if (_skippedFiles > 0) ...[
                      if (_failed > 0) const SizedBox(width: 8),
                      Text(l10n.aiBatchFileFailed(_skippedFiles),
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.orangeAccent)),
                    ],
                  ],
                ),
              ],
              // The new region: only after a run, so a file still being judged
              // never claims 「无检出高光」.
              if (!_running && hasResults) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome,
                        size: 14, color: Colors.amber),
                    const SizedBox(width: 6),
                    Text(
                      l10n.aiHighlightsTotal(totalHighlights(_results)),
                      key: const Key('ai_highlights_title'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 190,
                  child: ListView.builder(
                    key: const Key('ai_highlights'),
                    itemCount: highlights.length,
                    itemBuilder: (context, index) =>
                        _row(theme, l10n, highlights[index]),
                  ),
                ),
              ],
              if (hasResults) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(l10n.aiResultsTitle,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    Text(
                      l10n.aiHighlightCount(
                        _segments.where((s) => s.passed).length,
                        _segments.length,
                      ),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 220,
                  child: ListView.builder(
                    key: const Key('ai_results'),
                    itemCount: candidates.length,
                    itemBuilder: (context, index) =>
                        _row(theme, l10n, candidates[index]),
                  ),
                ),
              ],
              if (_savedPath != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 14, color: Colors.greenAccent),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SelectableText(
                        '${l10n.aiSavedTo}${_savedPath!}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (hasResults)
          TextButton(
            key: const Key('ai_reanalyze'),
            onPressed: _running ? null : _analyze,
            child: Text(l10n.aiReanalyze),
          ),
        TextButton(
          key: const Key('ai_save_project'),
          onPressed: canSave ? _saveProject : null,
          child: Text(l10n.aiSaveProject),
        ),
        TextButton(
          onPressed: () {
            _service?.cancel();
            _client?.cancel();
            Navigator.pop(context);
          },
          child: Text(l10n.close),
        ),
      ],
    );
  }

  Widget _row(ThemeData theme, AppStrings l10n, _Row row) {
    if (row is _GroupRow) return _groupHeader(theme, row);
    if (row is _NoteRow) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          row.text,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      );
    }
    final segment = (row as _SegmentRow);
    return segment.highlightOnly
        ? _highlightRow(theme, segment)
        : _candidateRow(theme, l10n, segment);
  }

  Widget _notice(ThemeData theme, String text, {required bool warning}) {
    final color = warning ? Colors.orangeAccent : theme.colorScheme.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        border: Border.all(color: color.withAlpha(120)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warning ? Icons.warning_amber : Icons.error_outline,
              size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(text,
                style: TextStyle(fontSize: 12, color: color, height: 1.5)),
          ),
        ],
      ),
    );
  }

  /// 「文件名 · 4 段高光」 — one file's group header in either list.
  Widget _groupHeader(ThemeData theme, _GroupRow row) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 2),
      child: Row(
        children: [
          const Icon(Icons.movie_outlined, size: 13, color: Colors.amber),
          const SizedBox(width: 6),
          Expanded(
            child: Tooltip(
              message: row.title,
              child: Text(
                row.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            row.trailing,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }

  /// One 「高光片段」 row: time · kind · the model's sentence. The whole row
  /// plays the segment through the existing preview window.
  Widget _highlightRow(ThemeData theme, _SegmentRow row) {
    final segment = row.segment;
    final description = segment.description.isEmpty
        ? (segment.error ?? '—')
        : segment.description;
    return InkWell(
      onTap: () => _openPreview(row.path, segment),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              child: Text(
                '${_clock(segment.startMs)}–${_clock(segment.endMs)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                row.kindLabel,
                style: TextStyle(fontSize: 11, color: Colors.amber.shade400),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Tooltip(
                message: description,
                child: Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            const Icon(Icons.play_circle_outline, size: 16),
          ],
        ),
      ),
    );
  }

  /// One candidate row — the list that existed before, unchanged except that
  /// the preview opens the file this candidate came from.
  Widget _candidateRow(ThemeData theme, AppStrings l10n, _SegmentRow row) {
    final segment = row.segment;
    final (label, color) = switch (segment.verdict) {
      AiVerdict.highlight => (
          l10n.aiVerdictHighlight,
          Colors.greenAccent.shade400
        ),
      AiVerdict.ordinary => (
          l10n.aiVerdictOrdinary,
          theme.colorScheme.onSurfaceVariant
        ),
      AiVerdict.unjudged => (l10n.aiVerdictUnjudged, Colors.orangeAccent),
    };
    final description = segment.description.isNotEmpty
        ? segment.description
        : (segment.error ?? '—');
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            '${_clock(segment.startMs)}–${_clock(segment.endMs)}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: TextStyle(fontSize: 11, color: color)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: description,
            child: Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        TextButton(
          onPressed: () => _openPreview(row.path, segment),
          child: Text(l10n.aiView),
        ),
      ],
    );
  }
}

/// 「查看」: plays the candidate window through the app's own player stack
/// (media_kit, same as the Top-5 preview) without touching the main player or
/// the open project.
class _SegmentPreviewDialog extends StatefulWidget {
  const _SegmentPreviewDialog({
    required this.title,
    required this.closeLabel,
    required this.filePath,
    required this.startMs,
    required this.endMs,
  });

  final String title;
  final String closeLabel;
  final String filePath;
  final int startMs;
  final int endMs;

  @override
  State<_SegmentPreviewDialog> createState() => _SegmentPreviewDialogState();
}

class _SegmentPreviewDialogState extends State<_SegmentPreviewDialog> {
  late final Player _player = Player();
  late final VideoController _controller = VideoController(_player);
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    try {
      await _player.open(Media(
        widget.filePath,
        start: Duration(milliseconds: widget.startMs),
        end: Duration(milliseconds: widget.endMs),
      ));
      await _player.play();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 640,
        height: 360,
        child: _error != null
            ? Text(_error!, style: const TextStyle(fontSize: 12))
            : ColoredBox(
                color: Colors.black,
                child: Video(
                  controller: _controller,
                  controls: NoVideoControls,
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.closeLabel),
        ),
      ],
    );
  }
}
