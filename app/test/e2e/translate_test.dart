// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/services/translate_service.dart';

/// Verify the translate pipeline: audio extraction + speech-to-text via
/// Windows System.Speech dictation grammar.
///
/// Generates a synthetic Chinese-speech MP4 via TTS, feeds it through the
/// full TranslateService pipeline, and asserts the output file format.
void main() {
  late String projectRoot;
  late String tempDir;
  late String ffmpegPath;
  late TranslateService service;

  setUpAll(() async {
    projectRoot = _resolveProjectRoot();
    tempDir = '$projectRoot\\temp\\e2e\\translate_test\\';
    Directory(tempDir).createSync(recursive: true);

    ffmpegPath = (await VideoProcessingService.findFfmpeg()) ?? '';
    if (ffmpegPath.isEmpty) {
      throw Exception('ffmpeg not found — cannot run translate e2e test');
    }
    service = TranslateService(ffmpegPath: ffmpegPath);
    print('ffmpeg: $ffmpegPath');
  });

  test('translateAll pipeline: TTS → MP4 → extract → transcribe', () async {
    // 1. Generate Chinese TTS audio via PowerShell + System.Speech.
    final ttsWav = '$tempDir\\tts_speech.wav';
    await _synthesizeSpeech(ttsWav, '你好世界测试语音识别功能');

    // 2. Mux TTS audio into a minimal MP4 video via ffmpeg.
    final testVideo = '$tempDir\\test_speech.mp4';
    final mux = await Process.run(ffmpegPath, [
      '-y',
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'color=black:size=320x240:d=3,format=yuv420p',
      '-i',
      ttsWav,
      '-shortest',
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-c:a',
      'aac',
      testVideo,
    ]);
    expect(mux.exitCode, 0, reason: 'ffmpeg mux failed:\n${mux.stderr}');
    expect(File(testVideo).existsSync(), isTrue);

    // 3. Run the full translate pipeline.
    final resultPath = '$tempDir\\translate_result.txt';
    await service.translateAll([testVideo], tempDir, resultPath);

    // 4. Verify output file.
    final resultFile = File(resultPath);
    expect(resultFile.existsSync(), isTrue, reason: 'translate_result.txt missing');
    final text = resultFile.readAsStringSync();
    print('TRANSLATE RESULT (${text.length} chars):\n$text');

    // Structure: "test_speech.mp4\n<text>\n\n"
    expect(text, contains('test_speech.mp4'), reason: 'filename header missing');
    final lines = text.split('\n');
    expect(lines.length, greaterThan(1), reason: 'result file too short');

    // With the preprocessing pipeline and clean TTS input, the recognizer
    // should produce real transcribed text — not the fallback placeholder.
    final content = lines[1].trim();
    expect(content.length, greaterThan(1),
        reason: 'transcription too short for known TTS input');
    expect(content, isNot(contains('(no speech detected)')),
        reason: 'should transcribe speech, not return fallback');
    expect(content, isNot(contains('(audio extraction failed)')),
        reason: 'extraction should succeed on valid video');

    // Clean up mp4; keep result for inspection.
    try {
      File(testVideo).deleteSync();
      File(ttsWav).deleteSync();
    } catch (_) {}
  }, timeout: const Timeout(Duration(minutes: 4)));
}

/// Generate a WAV file with synthesised Chinese speech via PowerShell.
Future<void> _synthesizeSpeech(String outputPath, String text) async {
  // Escape single quotes in the text.
  final safeText = text.replaceAll("'", "''");
  final scriptPath =
      '${Directory.systemTemp.path}\\hc_tts_gen_${DateTime.now().millisecondsSinceEpoch}.ps1';

  final script = '''
Add-Type -AssemblyName System.Speech
\$s = New-Object System.Speech.Synthesis.SpeechSynthesizer
\$s.SetOutputToWaveFile('${outputPath.replaceAll("'", "''")}')
\$s.Speak('$safeText')
\$s.Dispose()
''';

  try {
    File(scriptPath).writeAsStringSync(script);
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy', 'Bypass',
      '-File',
      scriptPath,
    ]);
    expect(result.exitCode, 0,
        reason: 'TTS PowerShell failed:\n${result.stderr}');
  } finally {
    try {
      File(scriptPath).deleteSync();
    } catch (_) {}
  }
}

String _resolveProjectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}\\AGENTS.md').existsSync() ||
        Directory('${dir.path}\\app').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
