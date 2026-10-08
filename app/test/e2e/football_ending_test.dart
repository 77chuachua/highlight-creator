// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';

void main() {
  late String projectRoot;
  late String tempDir;
  late String bgm;
  late String ffprobe;
  late VideoProcessingService service;

  setUpAll(() async {
    projectRoot = _resolveProjectRoot();
    tempDir = '$projectRoot\\temp\\e2e\\template_gen\\';
    final dir = Directory(tempDir);
    if (!dir.existsSync()) await dir.create(recursive: true);
    bgm = '$projectRoot\\test\\e2e\\default_templates\\Ending.mp4';
    expect(File(bgm).existsSync(), isTrue, reason: 'Ending.mp4 missing');

    VideoProcessingService.commandLogPath = '$projectRoot\\ffmpeg_command';

    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    service = VideoProcessingService(ffmpegPath: ffmpegPath);
    ffprobe = (ffmpegPath ?? '').replaceAll('ffmpeg.exe', 'ffprobe.exe');
    print('ffmpeg: ${ffmpegPath ?? "NOT FOUND (simulation mode)"}');
  });

  Future<bool> hasAudio(String path) async {
    if (!File(ffprobe).existsSync()) return true;
    final r = await Process.run(ffprobe, [
      '-v', 'error',
      '-select_streams', 'a',
      '-show_entries', 'stream=codec_type',
      '-of', 'csv=p=0',
      path,
    ]);
    return r.stdout.toString().contains('audio');
  }

  const titles = <int, String>{
    1: '感谢观看',
    2: 'THANKS FOR WATCHING',
    3: '精彩未完 下期再见',
    4: 'THE END',
    5: '订阅关注 不错过每一期',
  };

  for (final design in [1, 2, 3, 4, 5]) {
    test('ending design $design with audio (3s)', () async {
      VideoProcessingService.commandLogContext =
          'football_ending_test.dart :: design $design';
      final outputPath = '${tempDir}ending_football_$design.mp4';

      final result = await service.generateFootballEnding(
        outputPath: outputPath,
        design: design,
        title: titles[design],
        bgmPath: bgm,
        durationSecs: 3.0,
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      expect(await hasAudio(outputPath), isTrue, reason: 'no audio track');
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    }, timeout: const Timeout(Duration(minutes: 4)));
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
