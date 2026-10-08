// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';

/// Verify the three football-themed startup designs (4 s, with background
/// music) produce valid MP4s that contain an audio track, both with an empty
/// reserved text zone and with user-defined text drawn into that zone.
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
    bgm = '$projectRoot\\test\\e2e\\default_templates\\bg_music.mp3';
    expect(File(bgm).existsSync(), isTrue, reason: 'default bgm missing');

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

  const userText = <int, String>{
    1: '精彩进球集锦',
    2: 'MATCH HIGHLIGHTS',
    3: '最佳时刻 TOP GOALS',
  };

  for (final design in [1, 2, 3]) {
    test('football design $design reserved zone + bgm (4s)', () async {
      VideoProcessingService.commandLogContext =
          'football_startup_test.dart :: design $design reserved';
      final outputPath = '${tempDir}startup_football_$design.mp4';

      final result = await service.generateFootballStartup(
        outputPath: outputPath,
        design: design,
        bgmPath: bgm,
        durationSecs: 4.0,
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      expect(await hasAudio(outputPath), isTrue, reason: 'no audio track');
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    }, timeout: const Timeout(Duration(minutes: 4)));

    test('football design $design user text in reserved zone + bgm', () async {
      VideoProcessingService.commandLogContext =
          'football_startup_test.dart :: design $design text';
      final outputPath = '${tempDir}startup_football_${design}_text.mp4';

      final result = await service.generateFootballStartup(
        outputPath: outputPath,
        design: design,
        title: userText[design],
        bgmPath: bgm,
        durationSecs: 4.0,
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
