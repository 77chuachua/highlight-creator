// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';

void main() {
  late String projectRoot;
  late VideoProcessingService service;
  late String ffprobe;

  setUpAll(() async {
    projectRoot = _resolveProjectRoot();
    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    service = VideoProcessingService(ffmpegPath: ffmpegPath);
    ffprobe = (ffmpegPath ?? '').replaceAll('ffmpeg.exe', 'ffprobe.exe');
  });

  test('overlayText burns custom font/text onto an existing template',
      () async {
    final base = '$projectRoot\\temp\\e2e\\template_gen\\ending_football_4.mp4';
    if (!File(base).existsSync()) {
      // Self-sufficient base: generate it instead of depending on
      // template_generation_test having run first.
      Directory(File(base).parent.path).createSync(recursive: true);
      final gen = await service.generateFootballEnding(
        outputPath: base,
        design: 4,
        durationSecs: 3.0,
      );
      expect(gen.exitCode, 0, reason: 'base generation failed:\n${gen.stderr}');
    }
    expect(File(base).existsSync(), isTrue, reason: 'base template missing');

    final out = '$projectRoot\\temp\\e2e\\template_gen\\overlay_preview_test.mp4';
    const font = r'C:\Windows\Fonts\msyh.ttc';

    final res = await service.overlayText(
      inputPath: base,
      outputPath: out,
      text: '精彩进球集锦',
      fontPath: File(font).existsSync()
          ? font.replaceAll('\\', '/').replaceAll(':', r'\:')
          : null,
      fontSize: 52,
      fontColor: '#69F0AE',
      yExpr: 'h*0.15',
    );

    expect(res.exitCode, 0, reason: 'ffmpeg failed:\n${res.stderr}');
    final f = File(out);
    expect(f.existsSync(), isTrue);
    expect(f.lengthSync(), greaterThan(1000));

    final probe = await Process.run(ffprobe, [
      '-v', 'error',
      '-select_streams', 'a',
      '-show_entries', 'stream=codec_type',
      '-of', 'csv=p=0',
      out,
    ]);
    expect(probe.stdout.toString(), contains('audio'),
        reason: 'audio should be copied through');
    print('OK: $out  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
  });
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
