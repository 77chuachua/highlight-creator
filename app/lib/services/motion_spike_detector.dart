/// 画面运动 (screen-motion) candidate channel for 「AI 打点」: find the seconds
/// where the picture changes abruptly — a goal, a save or a shot pushes the
/// frame-to-frame difference far above what the rest of that minute shows.
///
/// This is the **primary** channel and the audio channel is the assistant
/// (`docs/ai_marking.md` §画面运动通道). The footage is an amateur pitch shot
/// from a fixed far stand: no referee, no whistle, and the crowd may or may not
/// cheer, so a loudness heuristic can never see a quiet save. The ball crossing
/// the line always moves pixels.
///
/// Two halves, deliberately kept apart:
///
/// * [MotionSpikeDetector.ffmpegArgs] + [MotionSpikeDetector.parseFrames] — the
///   ffmpeg command line and the `lavfi.signalstats.YAVG` parser;
/// * [MotionSpikeDetector.detect] — pure Dart, series in / candidates out, the
///   same local-baseline algorithm `audio_spike_detector.dart` proved out:
///   five 5 fps samples averaged into one 1 s window, `base[i]` = median of the
///   ±60 s neighbourhood, a hit is `motion[i] > 1.8 * base[i]` and
///   `motion[i] > 0.15 * median(motion)`, hits within 5 s merge, and each event
///   becomes an 8 s window from 6 s before its peak to 2 s after (at most 60,
///   sorted by time).
///
/// The ffmpeg run itself lives in `AiMarkingService.extractMotion`, which is
/// where cancellation and the temp-file lifecycle already are; this file only
/// builds the arguments, so the command can be read next to the parser that
/// depends on its output.
library;

import 'dart:math' as math;

/// One moment the motion channel wants the vision model to look at, in ms.
class MotionCandidate {
  const MotionCandidate({
    required this.startMs,
    required this.endMs,
    required this.peakMs,
    required this.peakMotion,
  });

  final int startMs;
  final int endMs;

  /// The most-changed second inside the event; the window starts `leadMs`
  /// before it.
  final int peakMs;

  /// Mean luma difference (0..255) of [peakMs], the ranking value. Only used to
  /// merge, rank and truncate candidates — never to decide "is this a goal".
  final double peakMotion;

  int get durationMs => endMs - startMs;

  @override
  String toString() => 'MotionCandidate(${startMs}..${endMs} ms, '
      'peak ${peakMs} ms @ ${peakMotion.toStringAsFixed(2)})';
}

/// The numbers [MotionSpikeDetector.detect] worked with, for the
/// `[ai-marking] motion ...` log line (docs/ai_marking.md §Logging).
///
/// Diagnostics only: nothing here feeds back into the decision.
class MotionDetectStats {
  const MotionDetectStats({
    required this.frames,
    required this.windows,
    required this.mean,
    required this.p95,
    required this.median,
    required this.spikeFactor,
    required this.noiseFloorRatio,
    required this.baselineWindowSec,
    required this.fps,
  });

  /// 5 fps samples parsed out of the metadata file.
  final int frames;

  /// 1 s windows the samples were averaged into.
  final int windows;

  /// `mean(motion)` over the 1 s windows — the `mean=` log field.
  final double mean;

  /// 95th percentile of the 1 s windows — the `p95=` log field, i.e. how loud
  /// the busiest 5 % of the match is. A file whose p95 barely clears its mean
  /// has no real motion peak anywhere.
  final double p95;

  /// `median(motion)`, the noise-floor reference.
  final double median;

  /// [MotionSpikeDetector.spikeFactor] (1.8).
  final double spikeFactor;

  /// [MotionSpikeDetector.noiseFloorRatio] (0.15).
  final double noiseFloorRatio;

  /// Half-width of the local-baseline window, in seconds (60).
  final int baselineWindowSec;

  /// [MotionSpikeDetector.fps] (5).
  final int fps;
}

/// A run of consecutive hit windows, in window indices.
class _Event {
  _Event(this.start, [int? end]) : end = end ?? start;

  final int start;
  int end;
}

/// Turns the per-frame luma difference series into candidate windows.
class MotionSpikeDetector {
  const MotionSpikeDetector._();

  /// Frames per second the ffmpeg filter samples: 5 is enough for an 8 s
  /// window and keeps the metadata file tiny (~2900 lines per minute).
  static const int fps = 5;

  static const int windowMs = 1000;

  /// 8 s window, shifted earlier: `peak - 6 s` .. `peak + 2 s` (the same
  /// asymmetry as the audio channel, docs/ai_marking.md §B).
  static const int leadMs = 6000;
  static const int tailMs = 2000;
  static const int maxCandidates = 60;
  static const double spikeFactor = 1.8;
  static const double noiseFloorRatio = 0.15;
  static const int baselineWindowSec = 60;
  static const int mergeGapMs = 5000;

  /// The motion scan, exactly the command `docs/ai_marking.md` §画面运动通道
  /// documents:
  ///
  /// ```
  /// ffmpeg -y -i <源> -vf "fps=5,scale=320:-2,format=gray,
  ///   tblend=all_mode=difference,signalstats,
  ///   metadata=print:file=<临时 txt>" -f null -
  /// ```
  ///
  /// `-an` drops the audio decode (it cannot change the video frames) and
  /// `-loglevel error` keeps a 12-minute run from spamming the captured stderr.
  static List<String> ffmpegArgs({
    required String sourcePath,
    required String metadataPath,
  }) =>
      [
        '-y',
        '-loglevel',
        'error',
        '-i',
        sourcePath,
        '-an',
        '-vf',
        'fps=$fps,scale=320:-2,format=gray,'
            'tblend=all_mode=difference,signalstats,'
            'metadata=print:file=${_filterPath(metadataPath)}',
        '-f',
        'null',
        '-',
      ];

  /// A path as a filter argument: ffmpeg splits filter options on `:`, so a
  /// Windows drive letter has to be escaped and the whole value quoted.
  ///
  /// ponytail: an apostrophe in the temp path would still break the quoting —
  /// that path is `%USERPROFILE%\HighlightCreator\temp`, i.e. the user name.
  static String _filterPath(String path) =>
      "'${path.replaceAll('\\', '/').replaceAll(':', r'\:')}'";

  /// The `lavfi.signalstats.YAVG` values of one `metadata=print` file, in
  /// frame order.
  ///
  /// Returns an empty list when the file holds no such line (a filter chain
  /// that silently produced nothing), so the caller can treat "no frames" as
  /// one failure instead of a crash.
  static List<double> parseFrames(String metadata) {
    const marker = 'lavfi.signalstats.YAVG=';
    final values = <double>[];
    for (final line in metadata.split('\n')) {
      final at = line.indexOf(marker);
      if (at < 0) continue;
      final value = double.tryParse(line.substring(at + marker.length).trim());
      if (value != null) values.add(value);
    }
    return values;
  }

  /// Candidates in timeline order; at most [maxCandidates].
  ///
  /// [durationMs] is the source video's length: the metadata can stop a frame
  /// short, and a candidate must not start past the end. [onStats] is a pure
  /// observer for the log and is not called when there is too little to
  /// measure.
  static List<MotionCandidate> detect(
    List<double> frames, {
    int? durationMs,
    void Function(MotionDetectStats stats)? onStats,
  }) {
    final perWindow = fps * windowMs ~/ 1000;
    if (perWindow < 2) return const <MotionCandidate>[];

    final motion = <double>[];
    for (var first = 0;
        first + perWindow <= frames.length;
        first += perWindow) {
      var sum = 0.0;
      for (var i = 0; i < perWindow; i++) {
        sum += frames[first + i];
      }
      motion.add(sum / perWindow);
    }
    if (motion.length < 2) return const <MotionCandidate>[];

    final median = _median(motion);
    final base = _localBaseline(motion);
    final noiseFloor = median * noiseFloorRatio;

    final hits = <_Event>[];
    for (var i = 0; i < motion.length; i++) {
      // The floor keeps a static passage's compression noise from becoming an
      // event just because its local baseline is even flatter.
      if (motion[i] <= noiseFloor) continue;
      if (motion[i] <= spikeFactor * base[i]) continue;
      if (hits.isNotEmpty && hits.last.end == i - 1) {
        hits.last.end = i;
      } else {
        hits.add(_Event(i));
      }
    }

    final events = <_Event>[];
    for (final event in hits) {
      if (events.isNotEmpty &&
          (event.start - events.last.end) * windowMs < mergeGapMs) {
        events.last.end = event.end;
      } else {
        events.add(_Event(event.start, event.end));
      }
    }

    final totalMs = durationMs ?? motion.length * windowMs;
    final candidates = <MotionCandidate>[];
    for (final event in events) {
      var peakIndex = event.start;
      for (var i = event.start + 1; i <= event.end; i++) {
        if (motion[i] > motion[peakIndex]) peakIndex = i;
      }
      final peakMotion = motion[peakIndex];
      final peakMs = peakIndex * windowMs + windowMs ~/ 2;
      final startMs = math.max(0, peakMs - leadMs);
      final endMs = math.min(totalMs, peakMs + tailMs);
      if (endMs - startMs < 1000) continue; // a degenerate edge, not a clip
      candidates.add(MotionCandidate(
        startMs: startMs,
        endMs: endMs,
        peakMs: peakMs,
        peakMotion: peakMotion,
      ));
    }

    if (candidates.length > maxCandidates) {
      candidates.sort((a, b) => b.peakMotion.compareTo(a.peakMotion));
      candidates.removeRange(maxCandidates, candidates.length);
    }
    candidates.sort((a, b) => a.startMs.compareTo(b.startMs));
    onStats?.call(MotionDetectStats(
      frames: frames.length,
      windows: motion.length,
      mean: _mean(motion),
      p95: _percentile(motion, 0.95),
      median: median,
      spikeFactor: spikeFactor,
      noiseFloorRatio: noiseFloorRatio,
      baselineWindowSec: baselineWindowSec,
      fps: fps,
    ));
    return candidates;
  }

  /// `base[i]` = median of the windows within [baselineWindowSec] of `i`,
  /// clipped at the file edges.
  ///
  /// ponytail: O(windows × span log span) — same order as the audio channel;
  /// only reach for a sliding window structure if the window count ever grows
  /// by orders of magnitude.
  static List<double> _localBaseline(List<double> motion) {
    final base = List<double>.filled(motion.length, 0);
    for (var i = 0; i < motion.length; i++) {
      final from = math.max(0, i - baselineWindowSec);
      final to = math.min(motion.length - 1, i + baselineWindowSec);
      base[i] = _median(motion.sublist(from, to + 1));
    }
    return base;
  }

  static double _mean(List<double> values) {
    if (values.isEmpty) return 0;
    var sum = 0.0;
    for (final value in values) {
      sum += value;
    }
    return sum / values.length;
  }

  /// Nearest-rank percentile: `values[floor(n * q)]`.
  static double _percentile(List<double> values, double q) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.of(values)..sort();
    return sorted[math.min(sorted.length - 1, (sorted.length * q).floor())];
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.of(values)..sort();
    final middle = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[middle]
        : (sorted[middle - 1] + sorted[middle]) / 2;
  }
}
