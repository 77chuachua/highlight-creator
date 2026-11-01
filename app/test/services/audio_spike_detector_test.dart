import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/services/audio_spike_detector.dart';

/// Two whistle-like bursts in a quiet match recording: the detector must find
/// exactly those, each as an 8 s window from 6 s before the burst to 2 s after.
void main() {
  const sampleRate = 16000;

  test('finds both whistles and puts peak-6s..peak+2s on each', () {
    final samples = _matchRecording(
      sampleRate: sampleRate,
      seconds: 60,
      bursts: const [(10.0, 1.5), (40.0, 1.5)],
    );
    final candidates = AudioSpikeDetector.detect(
      _wav(samples, sampleRate),
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
    final samples = _matchRecording(
      sampleRate: sampleRate,
      seconds: 12,
      bursts: const [(0.2, 1.2)],
    );
    final candidates = AudioSpikeDetector.detect(_wav(samples, sampleRate));

    expect(candidates, hasLength(1));
    expect(candidates.single.startMs, 0);
    // The loud window peaks at 0.5 s, so only 0.5 s + 2 s of window is left.
    expect(candidates.single.endMs, 2500);
  });

  test('clips the window at the end of the recording', () {
    final samples = _matchRecording(
      sampleRate: sampleRate,
      seconds: 12,
      bursts: const [(10.5, 1.2)],
    );
    final candidates = AudioSpikeDetector.detect(_wav(samples, sampleRate));

    expect(candidates, hasLength(1));
    expect(candidates.single.endMs, 12000);
    expect(candidates.single.startMs, 5500);
  });

  test('a quiet recording with no whistle yields no candidates', () {
    final samples = _matchRecording(
      sampleRate: sampleRate,
      seconds: 30,
      bursts: const [],
    );
    expect(
      AudioSpikeDetector.detect(_wav(samples, sampleRate)),
      isEmpty,
    );
  });

  test('caps a busy recording at 60 candidates', () {
    // 65 bursts 6 s apart: far enough to stay 65 events, so the cap must bite.
    final samples = _matchRecording(
      sampleRate: sampleRate,
      seconds: 395,
      bursts: [for (var i = 0; i < 65; i++) (i * 6.0 + 1.0, 0.8)],
    );
    final candidates = AudioSpikeDetector.detect(
      _wav(samples, sampleRate),
      durationMs: 395000,
    );

    expect(candidates, hasLength(60));
    expect(candidates.every((c) => c.startMs < c.endMs), isTrue);
  });

  test('rejects an empty file', () {
    expect(
      () => AudioSpikeDetector.detect(Uint8List(0)),
      throwsA(isA<FormatException>()),
    );
  });

  test('reports the thresholds it used, without changing the candidates', () {
    // Guard the tuned knobs themselves: the old global `median + 4*MAD` rule
    // is exactly what these replace, and drifting back would resurface the
    // missed highlights.
    expect(AudioSpikeDetector.strictEnergyFactor, 1.8);
    expect(AudioSpikeDetector.strictWhistleFactor, 1.5);
    expect(AudioSpikeDetector.relaxedEnergyFactor, 1.5);
    expect(AudioSpikeDetector.relaxedWhistleFactor, 1.3);
    expect(AudioSpikeDetector.baselineWindowSec, 60);
    expect(AudioSpikeDetector.maxCandidates, 60);

    final samples = _matchRecording(
      sampleRate: sampleRate,
      seconds: 60,
      bursts: const [(10.0, 1.5), (40.0, 1.5)],
    );
    AudioDetectStats? stats;
    final candidates = AudioSpikeDetector.detect(
      _wav(samples, sampleRate),
      durationMs: 60000,
      onStats: (value) => stats = value,
    );

    expect(candidates, hasLength(2));
    expect(stats, isNotNull);
    expect(stats!.zcrFactor, AudioSpikeDetector.zcrAboveMedian);
    expect(stats!.energyFactor, 1.8);
    expect(stats!.whistleFactor, 1.5);
    expect(stats!.baselineWindowSec, 60);
    // The log must be able to state whether the relaxed rerun was kept.
    expect(stats!.relaxed, isFalse);
    expect(stats!.median, greaterThan(0));
  });

  test('falls back to the relaxed factors when the strict pass is too sparse',
      () {
    // 0.028 amplitude: rms ≈ 0.0198, below the strict whistle multiple
    // (1.5 × 0.01414) but above the relaxed one (1.3 × 0.01414).
    final samples = _matchRecording(
      sampleRate: sampleRate,
      seconds: 60,
      bursts: const [(10.0, 1.5), (40.0, 1.5)],
      amplitude: 0.028,
    );
    AudioDetectStats? stats;
    final candidates = AudioSpikeDetector.detect(
      _wav(samples, sampleRate),
      durationMs: 60000,
      onStats: (value) => stats = value,
    );

    expect(candidates, hasLength(2));
    expect(stats, isNotNull);
    expect(stats!.relaxed, isTrue);
    expect(stats!.energyFactor, AudioSpikeDetector.relaxedEnergyFactor);
    expect(stats!.whistleFactor, AudioSpikeDetector.relaxedWhistleFactor);
  });

  test('local baseline finds pulses that the global median+MAD rule misses',
      () {
    final samples = _contaminatedRecording(sampleRate: sampleRate);

    // The old rule: one global threshold for the whole file. The 60 s of noise
    // put `median + 4*MAD` above both pulses, so it finds nothing at all.
    expect(_legacyPeakSeconds(samples, sampleRate), isEmpty);

    AudioDetectStats? stats;
    final candidates = AudioSpikeDetector.detect(
      _wav(samples, sampleRate),
      durationMs: 120000,
      onStats: (value) => stats = value,
    );

    bool covers(int seconds) => candidates.any(
          (c) => c.startMs <= seconds * 1000 && c.endMs >= seconds * 1000,
        );
    expect(covers(84), isTrue, reason: 'pulse at 84 s must be a candidate');
    expect(covers(94), isTrue, reason: 'pulse at 94 s must be a candidate');
    expect(stats, isNotNull);
    expect(stats!.energyFactor, 1.8);
    expect(stats!.whistleFactor, 1.5);
    expect(stats!.relaxed, isFalse);
  });

  test('rejects a WAV that is not PCM16 mono', () {
    final samples = _matchRecording(
      sampleRate: sampleRate,
      seconds: 2,
      bursts: const [],
    );
    final bytes = _wav(samples, sampleRate);
    // Byte 22 is the channel count in the fmt chunk.
    bytes[22] = 2;
    expect(
      () => AudioSpikeDetector.detect(bytes),
      throwsA(isA<FormatException>()),
    );
  });
}

/// Background hum plus [bursts] of high-frequency "whistle".
List<double> _matchRecording({
  required int sampleRate,
  required int seconds,
  required List<(double, double)> bursts,
  double amplitude = 0.5,
}) {
  final count = sampleRate * seconds;
  final samples = List<double>.filled(count, 0);
  for (var n = 0; n < count; n++) {
    samples[n] = 0.02 * math.sin(2 * math.pi * 200 * n / sampleRate);
  }
  for (final (startSeconds, lengthSeconds) in bursts) {
    final first = (startSeconds * sampleRate).round();
    final last = math.min(count, first + (lengthSeconds * sampleRate).round());
    for (var n = first; n < last; n++) {
      samples[n] = amplitude * math.sin(2 * math.pi * 3000 * n / sampleRate);
    }
  }
  return samples;
}

/// 60 s of loud white noise, then a quiet hum with two 1.5 s 3 kHz pulses at
/// 84 s and 94 s.
///
/// The noise raises the global `median + 4*MAD` above both pulses, while each
/// pulse is still dozens of times the RMS of its own ±60 s neighbourhood — the
/// exact situation the local baseline exists for.
List<double> _contaminatedRecording({required int sampleRate}) {
  const seconds = 120;
  final count = sampleRate * seconds;
  final samples = List<double>.filled(count, 0);
  for (var n = 0; n < count; n++) {
    samples[n] = 0.02 * math.sin(2 * math.pi * 200 * n / sampleRate);
  }

  // Uniform noise, RMS ≈ 0.30 / sqrt(3) ≈ 0.173 — much louder than the hum.
  final random = math.Random(20261029);
  for (var n = 0; n < 60 * sampleRate; n++) {
    samples[n] += 0.30 * (2 * random.nextDouble() - 1);
  }

  for (final startSeconds in const [84.0, 94.0]) {
    final first = (startSeconds * sampleRate).round();
    final last = first + (1.5 * sampleRate).round();
    for (var n = first; n < last; n++) {
      samples[n] += 0.65 * math.sin(2 * math.pi * 3000 * n / sampleRate);
    }
  }
  return samples;
}

/// The old global-threshold rule (replaced by the local baseline), kept only so
/// the regression test can prove what the local baseline fixed:
/// `rms > median + 4*MAD` AND `zcr > 1.3*median(zcr)` (retried once at 3*MAD
/// when it finds fewer than 10 events), with the same merge/8 s/cap pipeline.
/// Returns the peak second of each candidate.
List<int> _legacyPeakSeconds(List<double> samples, int sampleRate) {
  const windowMs = 1000;
  final perWindow = sampleRate * windowMs ~/ 1000;
  final rms = <double>[];
  final zcr = <double>[];
  for (var first = 0; first + perWindow <= samples.length; first += perWindow) {
    var sumSquares = 0.0;
    var crossings = 0;
    for (var i = 0; i < perWindow; i++) {
      final value = samples[first + i];
      sumSquares += value * value;
      if (i > 0 && (value >= 0) != (samples[first + i - 1] >= 0)) crossings++;
    }
    rms.add(math.sqrt(sumSquares / perWindow));
    zcr.add(crossings / (perWindow - 1));
  }
  if (rms.length < 2) return const <int>[];

  List<int> run(double madFactor) {
    final median = _median(rms);
    final mad = _median([for (final value in rms) (value - median).abs()]);
    final threshold = median + madFactor * mad;
    final zcrThreshold = _median(zcr) * 1.3;

    final hits = <(int, int)>[];
    for (var i = 0; i < rms.length; i++) {
      if (rms[i] <= threshold || zcr[i] <= zcrThreshold) continue;
      if (hits.isNotEmpty && hits.last.$2 == i - 1) {
        hits.last = (hits.last.$1, i);
      } else {
        hits.add((i, i));
      }
    }

    final merged = <(int, int)>[];
    for (final hit in hits) {
      if (merged.isNotEmpty && hit.$1 - merged.last.$2 < 5) {
        merged.last = (merged.last.$1, hit.$2);
      } else {
        merged.add(hit);
      }
    }
    return [
      for (final event in merged) _peakWindow(rms, event.$1, event.$2),
    ];
  }

  final strict = run(4);
  if (strict.length >= 10) return strict;
  final relaxed = run(3);
  return relaxed.length > strict.length ? relaxed : strict;
}

int _peakWindow(List<double> rms, int start, int end) {
  var peak = start;
  for (var i = start + 1; i <= end; i++) {
    if (rms[i] > rms[peak]) peak = i;
  }
  return peak;
}

double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = List<double>.of(values)..sort();
  final middle = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[middle]
      : (sorted[middle - 1] + sorted[middle]) / 2;
}

/// Minimal 44-byte-header PCM16 mono WAV.
Uint8List _wav(List<double> samples, int sampleRate) {
  const channels = 1;
  const bits = 16;
  final dataSize = samples.length * 2;
  final bytes = Uint8List(44 + dataSize);
  final view = ByteData.sublistView(bytes);

  void tag(int at, String value) {
    for (var i = 0; i < 4; i++) {
      bytes[at + i] = value.codeUnitAt(i);
    }
  }

  tag(0, 'RIFF');
  view.setUint32(4, 36 + dataSize, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little); // PCM
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * channels * bits ~/ 8, Endian.little);
  view.setUint16(32, channels * bits ~/ 8, Endian.little);
  view.setUint16(34, bits, Endian.little);
  tag(36, 'data');
  view.setUint32(40, dataSize, Endian.little);

  for (var i = 0; i < samples.length; i++) {
    final value = (samples[i] * 32767).round().clamp(-32768, 32767);
    view.setInt16(44 + i * 2, value, Endian.little);
  }
  return bytes;
}
