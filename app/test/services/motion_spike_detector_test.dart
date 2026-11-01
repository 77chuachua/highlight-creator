import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/services/ai_marking_service.dart';
import 'package:highlight_creator/services/audio_spike_detector.dart';
import 'package:highlight_creator/services/motion_spike_detector.dart';

/// The 画面运动 channel: a flat 5 fps luma-difference series with two short
/// bursts must produce exactly those two 8 s windows (`peak - 6 s` ..
/// `peak + 2 s`), and the merge must tell "motion only" (the 01:24 save nobody
/// shouted about) from "both".
void main() {
  group('MotionSpikeDetector', () {
    test('finds both bursts and builds peak-6s..peak+2s on each', () {
      final frames = _series(seconds: 60, bursts: const [(10, 1), (40, 1)]);
      final candidates = MotionSpikeDetector.detect(
        frames,
        durationMs: 60000,
      );

      expect(candidates, hasLength(2));
      expect(candidates[0].startMs, 4500);
      expect(candidates[0].endMs, 12500);
      expect(candidates[0].peakMs, 10500);
      expect(candidates[1].startMs, 34500);
      expect(candidates[1].endMs, 42500);
    });

    test('clips the window at the start of the recording', () {
      final candidates = MotionSpikeDetector.detect(
        _series(seconds: 12, bursts: const [(0, 1)]),
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.startMs, 0);
      expect(candidates.single.endMs, 2500);
    });

    test('clips the window at the end of the recording', () {
      final candidates = MotionSpikeDetector.detect(
        _series(seconds: 12, bursts: const [(11, 1)]),
      );

      expect(candidates, hasLength(1));
      expect(candidates.single.startMs, 5500);
      expect(candidates.single.endMs, 12000);
    });

    test('a flat recording yields no candidates', () {
      expect(
        MotionSpikeDetector.detect(_series(seconds: 30, bursts: const [])),
        isEmpty,
      );
    });

    test('caps a busy recording at 60 candidates', () {
      // 65 one-second bursts 6 s apart: 6 s > the 5 s merge gap, so the cap is
      // what has to bite.
      final candidates = MotionSpikeDetector.detect(
        _series(
          seconds: 395,
          bursts: [for (var i = 0; i < 65; i++) (i * 6 + 1, 1)],
        ),
        durationMs: 395000,
      );

      expect(candidates, hasLength(60));
      expect(candidates.every((c) => c.startMs < c.endMs), isTrue);
    });

    test('reports the series it measured, without changing the candidates', () {
      // Guard the tuned knobs themselves (docs/ai_marking.md §画面运动通道).
      expect(MotionSpikeDetector.fps, 5);
      expect(MotionSpikeDetector.spikeFactor, 1.8);
      expect(MotionSpikeDetector.noiseFloorRatio, 0.15);
      expect(MotionSpikeDetector.baselineWindowSec, 60);
      expect(MotionSpikeDetector.maxCandidates, 60);

      MotionDetectStats? stats;
      final candidates = MotionSpikeDetector.detect(
        _series(seconds: 60, bursts: const [(10, 1), (40, 1)]),
        durationMs: 60000,
        onStats: (value) => stats = value,
      );

      expect(candidates, hasLength(2));
      expect(stats, isNotNull);
      expect(stats!.frames, 300);
      expect(stats!.windows, 60);
      expect(stats!.fps, 5);
      expect(stats!.median, closeTo(1.2, 1e-9));
      expect(stats!.mean, greaterThan(0));
      expect(stats!.p95, greaterThanOrEqualTo(stats!.median));
    });

    test('too few frames to measure a window yields nothing', () {
      MotionDetectStats? stats;
      final candidates = MotionSpikeDetector.detect(
        const [1, 2, 3, 4],
        onStats: (value) => stats = value,
      );

      expect(candidates, isEmpty);
      expect(stats, isNull);
    });

    test('parseFrames reads YAVG and ignores the rest of the metadata', () {
      const metadata = 'frame:0    pts:1       pts_time:0.2\n'
          'lavfi.signalstats.YMIN=0\n'
          'lavfi.signalstats.YLOW=0\n'
          'lavfi.signalstats.YAVG=1.18877\n'
          'frame:1    pts:2       pts_time:0.4\n'
          'lavfi.signalstats.YAVG=2.5\n';
      expect(
        MotionSpikeDetector.parseFrames(metadata),
        [1.18877, 2.5],
      );
      expect(MotionSpikeDetector.parseFrames(''), isEmpty);
      expect(MotionSpikeDetector.parseFrames('no stats here'), isEmpty);
    });

    test('ffmpeg arguments keep the windows drive colon escaped', () {
      final args = MotionSpikeDetector.ffmpegArgs(
        sourcePath: r'C:\videos\a.mp4',
        metadataPath: r'C:\temp\ai_marking\a.motion.txt',
      );
      final filter = args[args.indexOf('-vf') + 1];

      expect(filter, contains('fps=5'));
      expect(filter, contains('tblend=all_mode=difference'));
      expect(filter, contains('metadata=print:file='));
      // The path is quoted and `C:` is written `C\:`; ffmpeg splits options
      // on `:` and would otherwise read `file=C`.
      expect(filter, contains(r"file='C\:/temp/ai_marking/a.motion.txt'"));
      expect(args, contains('-an'));
      expect(args.sublist(args.length - 3), ['-f', 'null', '-']);
    });
  });

  group('mergeCandidateChannels', () {
    test('keeps a motion-only moment that audio never saw', () {
      final merged = mergeCandidateChannels(
        audio: const [
          AudioCandidate(
            startMs: 196000,
            endMs: 204000,
            peakMs: 200000,
            peakRms: 0.4,
          ),
        ],
        motion: const [
          MotionCandidate(
            startMs: 82000,
            endMs: 90000,
            peakMs: 86000,
            peakMotion: 11.5,
          ),
          MotionCandidate(
            startMs: 196000,
            endMs: 204000,
            peakMs: 200500,
            peakMotion: 8.7,
          ),
        ],
      );

      expect(merged, hasLength(2));
      expect(merged[0].source, AiCandidateSource.motion);
      expect(merged[0].peakRms, 0);
      expect(merged[0].motionPeak, 11.5);
      expect(merged[1].source, AiCandidateSource.both);
      expect(merged[1].startMs, 196000);
      expect(merged[1].endMs, 204000);
    });

    test('merges windows overlapping more than half into their union', () {
      final merged = mergeCandidateChannels(
        audio: const [
          AudioCandidate(
            startMs: 0,
            endMs: 8000,
            peakMs: 4000,
            peakRms: 0.3,
          ),
        ],
        motion: const [
          MotionCandidate(
            startMs: 3500,
            endMs: 11500,
            peakMs: 7500,
            peakMotion: 9,
          ),
        ],
      );

      expect(merged, hasLength(1));
      expect(merged.single.source, AiCandidateSource.both);
      // 11.5 s union, trimmed to peak - 6 s .. peak + 2 s (motion peak 7500).
      expect(merged.single.startMs, 1500);
      expect(merged.single.endMs, 9500);
    });

    test('exactly half overlap stays two candidates', () {
      final merged = mergeCandidateChannels(
        audio: const [
          AudioCandidate(
            startMs: 0,
            endMs: 8000,
            peakMs: 4000,
            peakRms: 0.3,
          ),
        ],
        motion: const [
          MotionCandidate(
            startMs: 4000,
            endMs: 12000,
            peakMs: 8000,
            peakMotion: 9,
          ),
        ],
      );

      expect(merged, hasLength(2));
      expect(merged[0].source, AiCandidateSource.audio);
      expect(merged[1].source, AiCandidateSource.motion);
    });

    test('caps at 60, keeping both-channel rows first', () {
      // 30 rows both, 20 motion-only, 20 audio-only, far enough apart to stay
      // separate: 70 in, 60 out.
      final audio = <AudioCandidate>[
        for (var i = 0; i < 30; i++)
          AudioCandidate(
            startMs: i * 10000,
            endMs: i * 10000 + 8000,
            peakMs: i * 10000 + 4000,
            peakRms: 0.5,
          ),
        for (var i = 0; i < 20; i++)
          AudioCandidate(
            startMs: (i + 200) * 10000,
            endMs: (i + 200) * 10000 + 8000,
            peakMs: (i + 200) * 10000 + 4000,
            peakRms: 0.9,
          ),
      ];
      final motion = <MotionCandidate>[
        for (var i = 0; i < 30; i++)
          MotionCandidate(
            startMs: i * 10000,
            endMs: i * 10000 + 8000,
            peakMs: i * 10000 + 4000,
            peakMotion: 3,
          ),
        for (var i = 0; i < 20; i++)
          MotionCandidate(
            startMs: (i + 100) * 10000,
            endMs: (i + 100) * 10000 + 8000,
            peakMs: (i + 100) * 10000 + 4000,
            peakMotion: 9,
          ),
      ];

      final merged = mergeCandidateChannels(audio: audio, motion: motion);
      int count(AiCandidateSource source) =>
          merged.where((s) => s.source == source).length;

      expect(merged, hasLength(60));
      expect(count(AiCandidateSource.both), 30);
      expect(count(AiCandidateSource.motion), 20);
      expect(count(AiCandidateSource.audio), 10);
      expect(merged.first.startMs, 0);
      expect(merged.last.startMs, greaterThan(merged.first.startMs));
    });
  });
}

/// A flat 5 fps luma-difference series: [baseline] everywhere, [peak] for the
/// seconds in [bursts] (`(startSecond, seconds)`).
List<double> _series({
  required int seconds,
  required List<(int, int)> bursts,
  double baseline = 1.2,
  double peak = 9.0,
}) {
  return [
    for (var n = 0; n < seconds * MotionSpikeDetector.fps; n++)
      bursts.any((burst) {
        final second = n ~/ MotionSpikeDetector.fps;
        return second >= burst.$1 && second < burst.$1 + burst.$2;
      })
          ? peak
          : baseline,
  ];
}
