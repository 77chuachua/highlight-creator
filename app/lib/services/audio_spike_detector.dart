/// Candidate detection for 「AI 打点」: find the loud, whistle-like seconds of a
/// match recording without any model or ffmpeg involved.
///
/// Pure Dart — bytes in, windows out — so the whole heuristic is verifiable
/// with a synthesised waveform (`test/services/audio_spike_detector_test.dart`)
/// instead of a 12-minute video and a network call.
///
/// The rule (fixed by docs/ai_marking.md, do not tune silently):
///
/// * measure 1 s windows: RMS and zero-crossing rate (ZCR);
/// * local baseline `base[i]` = median RMS of the ±60 s neighbourhood, so one
///   loud stretch cannot raise the bar for a highlight a minute away;
/// * a hit is either `rms > 1.8 * base` (energy) or
///   `zcr > 1.3 * median(zcr)` and `rms > 1.5 * base` (whistle), and always
///   `rms > 0.15 * median(rms)` (noise floor: an air conditioner is not an
///   event);
/// * consecutive hits merge into one event, events less than 5 s apart merge;
/// * an event becomes an 8 s candidate from 6 s before its loudest second to
///   2 s after it (the cheer lags the goal by 1–3 s), clipped at the file edges;
/// * more than 60 events: keep the 60 loudest; fewer than 10: retry once with
///   the energy factor at 1.5 and the whistle factor at 1.3.
library;

import 'dart:math' as math;
import 'dart:typed_data';

/// One moment worth asking the vision model about, in milliseconds.
class AudioCandidate {
  const AudioCandidate({
    required this.startMs,
    required this.endMs,
    required this.peakMs,
    required this.peakRms,
  });

  final int startMs;
  final int endMs;

  /// The loudest second inside the event; the window starts `leadMs` before it.
  final int peakMs;

  /// Loudness of [peakMs], 0..1. Only used to rank and truncate candidates.
  final double peakRms;

  int get durationMs => endMs - startMs;

  @override
  String toString() => 'AudioCandidate(${startMs}..${endMs} ms, '
      'peak ${peakMs} ms @ ${peakRms.toStringAsFixed(3)})';
}

/// The thresholds [AudioSpikeDetector.detect] actually used, for the
/// `[ai-marking] detect ...` log line (docs/ai_marking.md §Logging).
///
/// Diagnostics only: nothing here feeds back into the decision, and a caller
/// that ignores it is unaffected.
class AudioDetectStats {
  const AudioDetectStats({
    required this.median,
    required this.energyFactor,
    required this.whistleFactor,
    required this.zcrFactor,
    required this.baselineWindowSec,
    required this.relaxed,
  });

  /// `median(rms)` over the 1 s windows: the noise-floor reference, no longer
  /// the per-window threshold (that is [energyFactor] × the local baseline).
  final double median;

  /// Energy-channel multiple kept: [AudioSpikeDetector.strictEnergyFactor] or
  /// [AudioSpikeDetector.relaxedEnergyFactor].
  final double energyFactor;

  /// Whistle-channel RMS multiple kept: [AudioSpikeDetector.strictWhistleFactor]
  /// or [AudioSpikeDetector.relaxedWhistleFactor]. The ZCR side is always
  /// [zcrFactor] × `median(zcr)`.
  final double whistleFactor;

  /// [AudioSpikeDetector.zcrAboveMedian].
  final double zcrFactor;

  /// Half-width of the local-baseline window, in seconds
  /// ([AudioSpikeDetector.baselineWindowSec]).
  final int baselineWindowSec;

  /// True when the strict pass found too few events and the relaxed rerun is
  /// the one that produced the candidates.
  final bool relaxed;
}

/// A RIFF/WAVE file holding 16-bit mono PCM — exactly what
/// `ffmpeg -ac 1 -ar 16000 -f wav` writes.
class Pcm16Wav {
  Pcm16Wav._({
    required this.sampleRate,
    required this.channels,
    required Uint8List bytes,
    required this.dataOffset,
    required this.dataSize,
  }) : _bytes = bytes;

  final int sampleRate;
  final int channels;
  final int dataOffset;
  final int dataSize;
  final Uint8List _bytes;

  int get sampleCount => dataSize ~/ 2;

  int get durationMs => sampleRate == 0 ? 0 : sampleCount * 1000 ~/ sampleRate;

  /// Sample [index] as a signed 16-bit value (-32768..32767).
  int sampleAt(int index) {
    final at = dataOffset + index * 2;
    final raw = _bytes[at] | (_bytes[at + 1] << 8);
    return raw >= 0x8000 ? raw - 0x10000 : raw;
  }

  /// Parse a PCM16 WAV. Throws [FormatException] for anything else: the caller
  /// controls the ffmpeg command line, so a wrong format is a bug, not input.
  static Pcm16Wav parse(Uint8List bytes) {
    if (bytes.length < 44) throw const FormatException('not a WAV file');
    if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') {
      throw const FormatException('not a RIFF/WAVE file');
    }

    var format = 0;
    var channels = 0;
    var sampleRate = 0;
    var bits = 0;
    var offset = 12;
    int? dataOffset;
    int? dataSize;

    while (offset + 8 <= bytes.length) {
      final id = _tag(bytes, offset);
      final size = _u32(bytes, offset + 4);
      final body = offset + 8;
      if (id == 'fmt ') {
        if (body + 16 > bytes.length) {
          throw const FormatException('truncated fmt chunk');
        }
        format = _u16(bytes, body);
        channels = _u16(bytes, body + 2);
        sampleRate = _u32(bytes, body + 4);
        bits = _u16(bytes, body + 14);
      } else if (id == 'data') {
        dataOffset = body;
        // A streamed WAV may carry 0xFFFFFFFF; trust the file length instead.
        dataSize = math.min(size, bytes.length - body);
      }
      if (size <= 0) break; // corrupt length: stop rather than spin
      // RIFF chunks are padded to an even number of bytes.
      offset = body + size + (size.isOdd ? 1 : 0);
    }

    if (dataOffset == null || dataSize == null || dataSize <= 0) {
      throw const FormatException('WAV has no audio data');
    }
    if (format != 1) throw FormatException('WAV is not PCM (format $format)');
    if (bits != 16) throw FormatException('WAV is not 16-bit (bits $bits)');
    if (channels != 1) {
      throw FormatException('WAV is not mono ($channels channels)');
    }
    if (sampleRate <= 0) throw const FormatException('WAV has no sample rate');

    return Pcm16Wav._(
      sampleRate: sampleRate,
      channels: channels,
      bytes: bytes,
      dataOffset: dataOffset,
      dataSize: dataSize,
    );
  }

  static String _tag(Uint8List bytes, int at) =>
      String.fromCharCodes(bytes, at, at + 4);

  static int _u16(Uint8List bytes, int at) => bytes[at] | (bytes[at + 1] << 8);

  static int _u32(Uint8List bytes, int at) =>
      bytes[at] |
      (bytes[at + 1] << 8) |
      (bytes[at + 2] << 16) |
      (bytes[at + 3] << 24);
}

/// A run of consecutive hit windows, in window indices.
class _Event {
  _Event(this.start, [int? end]) : end = end ?? start;

  final int start;
  int end;
}

/// Turns a WAV into candidate windows. See the library comment for the rule.
class AudioSpikeDetector {
  const AudioSpikeDetector._();

  static const int windowMs = 1000;

  /// 8 s window, shifted earlier: `peak - 6 s` .. `peak + 2 s`.
  ///
  /// The crowd reacts 1–3 s after the ball crosses the line, so a window
  /// centred on the sound peak puts the decisive moment too late (docs/
  /// ai_marking.md §B). The three tile views still cover the full 8 s.
  static const int leadMs = 6000;
  static const int tailMs = 2000;
  static const int maxCandidates = 60;
  static const int minEvents = 10;
  static const double strictEnergyFactor = 1.8;
  static const double strictWhistleFactor = 1.5;
  static const double relaxedEnergyFactor = 1.5;
  static const double relaxedWhistleFactor = 1.3;
  static const double zcrAboveMedian = 1.3;
  static const double noiseFloorRatio = 0.15;
  static const int baselineWindowSec = 60;
  static const int mergeGapMs = 5000;

  /// Candidates in timeline order; at most [maxCandidates].
  ///
  /// [durationMs] is the source video's length: the WAV can be a few
  /// milliseconds shorter, and a candidate must not start past the end.
  ///
  /// [onStats] is a pure observer for the log; it is not called when the WAV
  /// is too short to measure anything.
  static List<AudioCandidate> detect(
    Uint8List wavBytes, {
    int? durationMs,
    void Function(AudioDetectStats stats)? onStats,
  }) {
    final wav = Pcm16Wav.parse(wavBytes);
    final samplesPerWindow = wav.sampleRate * windowMs ~/ 1000;
    if (samplesPerWindow < 2) return const <AudioCandidate>[];

    final rms = <double>[];
    final zcr = <double>[];
    // One pass over the PCM, accumulating per window: no 23 MB sample list.
    for (var first = 0;
        first + samplesPerWindow <= wav.sampleCount;
        first += samplesPerWindow) {
      var sumSquares = 0.0;
      var crossings = 0;
      var previous = 0;
      for (var i = 0; i < samplesPerWindow; i++) {
        final sample = wav.sampleAt(first + i);
        final value = sample / 32768.0;
        sumSquares += value * value;
        if (i > 0 && (sample >= 0) != (previous >= 0)) crossings++;
        previous = sample;
      }
      rms.add(math.sqrt(sumSquares / samplesPerWindow));
      zcr.add(crossings / (samplesPerWindow - 1));
    }
    if (rms.length < 2) return const <AudioCandidate>[];

    final rmsMedian = _median(rms);
    final zcrMedian = _median(zcr);
    final base = _localBaseline(rms);

    var energyFactor = strictEnergyFactor;
    var whistleFactor = strictWhistleFactor;
    var relaxed = false;
    var events = _events(
      rms,
      zcr,
      base,
      zcrMedian,
      rmsMedian,
      energyFactor,
      whistleFactor,
    );
    if (events.length < minEvents) {
      final relaxedEvents = _events(
        rms,
        zcr,
        base,
        zcrMedian,
        rmsMedian,
        relaxedEnergyFactor,
        relaxedWhistleFactor,
      );
      // A lower threshold can only add hits, but the 5 s merge can then fold
      // them into *fewer* events — keep whichever run found more.
      if (relaxedEvents.length > events.length) {
        events = relaxedEvents;
        energyFactor = relaxedEnergyFactor;
        whistleFactor = relaxedWhistleFactor;
        relaxed = true;
      }
    }

    final totalMs = durationMs ?? wav.durationMs;
    final candidates = <AudioCandidate>[];
    for (final event in events) {
      var peakIndex = event.start;
      for (var i = event.start + 1; i <= event.end; i++) {
        if (rms[i] > rms[peakIndex]) peakIndex = i;
      }
      final peakRms = rms[peakIndex];
      final peakMs = peakIndex * windowMs + windowMs ~/ 2;
      final startMs = math.max(0, peakMs - leadMs);
      final endMs = math.min(totalMs, peakMs + tailMs);
      if (endMs - startMs < 1000) continue; // a degenerate edge, not a clip
      candidates.add(AudioCandidate(
        startMs: startMs,
        endMs: endMs,
        peakMs: peakMs,
        peakRms: peakRms,
      ));
    }

    if (candidates.length > maxCandidates) {
      candidates.sort((a, b) => b.peakRms.compareTo(a.peakRms));
      candidates.removeRange(maxCandidates, candidates.length);
    }
    candidates.sort((a, b) => a.startMs.compareTo(b.startMs));
    onStats?.call(AudioDetectStats(
      median: rmsMedian,
      energyFactor: energyFactor,
      whistleFactor: whistleFactor,
      zcrFactor: zcrAboveMedian,
      baselineWindowSec: baselineWindowSec,
      relaxed: relaxed,
    ));
    return candidates;
  }

  /// `base[i]` = median RMS of the windows within [baselineWindowSec] of `i`,
  /// clipped at the file edges.
  ///
  /// ponytail: O(windows × span log span) — 690 windows × 121 values is noise
  /// beside the PCM pass itself; only reach for a sliding window structure if
  /// the window count ever grows by orders of magnitude.
  static List<double> _localBaseline(List<double> rms) {
    final base = List<double>.filled(rms.length, 0);
    for (var i = 0; i < rms.length; i++) {
      final from = math.max(0, i - baselineWindowSec);
      final to = math.min(rms.length - 1, i + baselineWindowSec);
      base[i] = _median(rms.sublist(from, to + 1));
    }
    return base;
  }

  /// Loud-or-whistle-y windows, merged into events.
  static List<_Event> _events(
    List<double> rms,
    List<double> zcr,
    List<double> base,
    double zcrMedian,
    double rmsMedian,
    double energyFactor,
    double whistleFactor,
  ) {
    final zcrThreshold = zcrMedian * zcrAboveMedian;
    final noiseFloor = rmsMedian * noiseFloorRatio;

    final hits = <_Event>[];
    for (var i = 0; i < rms.length; i++) {
      // The floor keeps an air conditioner in a dead-quiet passage from
      // becoming an event just because its local baseline is even quieter.
      if (rms[i] <= noiseFloor) continue;
      final energy = rms[i] > energyFactor * base[i];
      final whistle = zcr[i] > zcrThreshold && rms[i] > whistleFactor * base[i];
      if (!energy && !whistle) continue;
      if (hits.isNotEmpty && hits.last.end == i - 1) {
        hits.last.end = i;
      } else {
        hits.add(_Event(i));
      }
    }

    final merged = <_Event>[];
    for (final event in hits) {
      if (merged.isNotEmpty &&
          (event.start - merged.last.end) * windowMs < mergeGapMs) {
        merged.last.end = event.end;
      } else {
        merged.add(_Event(event.start, event.end));
      }
    }
    return merged;
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
