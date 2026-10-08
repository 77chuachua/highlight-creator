import 'dart:convert';
import 'dart:io';

/// Standalone service for extracting audio from video files and transcribing
/// speech to text via the Windows built-in System.Speech recognition engine.
///
/// No network, no API keys, no third-party dependencies — uses PowerShell to
/// drive System.Speech.Recognition.SpeechRecognitionEngine with dictation
/// grammar for offline, keyless speech-to-text.
class TranslateService {
  final String ffmpegPath;

  const TranslateService({required this.ffmpegPath});

  /// Translate all source videos: extract audio, transcribe, write one
  /// combined result file.
  ///
  /// Output format per file:
  /// ```
  /// filename.mp4
  /// <transcribed text>
  ///
  /// nextfile.mp4
  /// <transcribed text>
  /// ```
  Future<String> translateAll(
    List<String> sourcePaths,
    String tempDir,
    String resultPath,
  ) async {
    final buf = StringBuffer();

    for (final videoPath in sourcePaths) {
      final filename = videoPath.split('\\').last;
      buf.writeln(filename);

      final wavPath = '$tempDir\\${filename}_audio.wav';
      final ok = await _extractAudio(videoPath, wavPath);
      if (ok) {
        final text = await _transcribe(wavPath);
        buf.writeln(text.isNotEmpty ? text : '(no speech detected)');
        // Clean up temp WAV.
        try {
          File(wavPath).deleteSync();
        } catch (_) {}
      } else {
        buf.writeln('(audio extraction failed)');
      }
      buf.writeln(); // blank line separator
    }

    final file = File(resultPath);
    await file.writeAsString(buf.toString(), encoding: utf8);
    return resultPath;
  }

  /// Extract the audio stream as 16 kHz mono 16-bit PCM WAV via ffmpeg.
  ///
  /// Applies audio preprocessing to improve speech recognition accuracy:
  /// - highpass 200 Hz: remove low-frequency rumble
  /// - compand: dynamic-range compression (bring quiet speech forward)
  /// - loudnorm: loudness normalization
  /// - volume 1.5×: boost signal for the recognizer
  Future<bool> _extractAudio(String videoPath, String outputWavPath) async {
    try {
      final result = await Process.run(ffmpegPath, [
        '-y',
        '-v',
        'error',
        '-i',
        videoPath,
        '-vn', // drop video
        '-acodec',
        'pcm_s16le',
        '-ar',
        '16000',
        '-ac',
        '1',
        '-af',
        ('highpass=f=200,compand=attacks=0.01:decays=0.2:'
            'points=-80/-80|-30/-20|-20/-10|0/0,loudnorm,volume=1.5'),
        outputWavPath,
      ]);
      return result.exitCode == 0 && File(outputWavPath).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Transcribe a 16 kHz mono PCM WAV to text via PowerShell + System.Speech.
  static Future<String> _transcribe(String wavPath) async {
    // Write a temp PowerShell script — avoids quoting-hell with -Command.
    final scriptPath =
        '${Directory.systemTemp.path}\\hc_stt_${DateTime.now().millisecondsSinceEpoch}.ps1';

    // Use single-quote PS strings for path safety; escape embedded single-quotes.
    final safeWav = wavPath.replaceAll("'", "''");

    final script = '''
Add-Type -AssemblyName System.Speech
\$culture = [System.Globalization.CultureInfo]::new('zh-CN')
\$engine = New-Object System.Speech.Recognition.SpeechRecognitionEngine(\$culture)
\$engine.LoadGrammar((New-Object System.Speech.Recognition.DictationGrammar))
\$engine.SetInputToWaveFile('$safeWav')
\$r = \$engine.Recognize()
if (\$null -eq \$r) { Write-Output '' } else { Write-Output \$r.Text }
\$engine.Dispose()
''';

    try {
      File(scriptPath).writeAsStringSync(script, encoding: utf8);
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy', 'Bypass',
        '-File',
        scriptPath,
      ]);
      if (result.exitCode == 0) {
        return (result.stdout as String).trim();
      }
      return '';
    } catch (_) {
      return '';
    } finally {
      try {
        File(scriptPath).deleteSync();
      } catch (_) {}
    }
  }
}
