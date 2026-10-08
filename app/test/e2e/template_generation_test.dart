// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/services/template_generator_service.dart';

/// Verify that generateStartupTemplate, generateEndingTemplate, and
/// generateTransitionTemplate produce valid MP4 files in temp/.
void main() {
  late String projectRoot;
  late String tempDir;
  late VideoProcessingService service;
  late String? ffmpegPath;

  setUpAll(() async {
    projectRoot = _resolveProjectRoot();
    tempDir = '$projectRoot\\temp\\e2e\\template_gen\\';
    final dir = Directory(tempDir);
    if (!dir.existsSync()) await dir.create(recursive: true);

    VideoProcessingService.commandLogPath = '$projectRoot\\ffmpeg_command';

    ffmpegPath = await VideoProcessingService.findFfmpeg();
    service = VideoProcessingService(ffmpegPath: ffmpegPath);
    print('ffmpeg: ${ffmpegPath ?? "NOT FOUND (simulation mode)"}');
  });

  group('generateStartupTemplate', () {
    test('green style with Chinese title', () async {
      VideoProcessingService.commandLogContext =
          'template_generation_test.dart :: startup green Chinese';
      final outputPath = '${tempDir}startup_green.mp4';

      final result = await service.generateStartupTemplate(
        outputPath: outputPath,
        title: '足球精彩集锦',
        subtitle: '2026 Season Highlights',
        style: 'green',
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });

    test('dark style', () async {
      VideoProcessingService.commandLogContext =
          'template_generation_test.dart :: startup dark';
      final outputPath = '${tempDir}startup_dark.mp4';

      final result = await service.generateStartupTemplate(
        outputPath: outputPath,
        title: 'Match Day',
        subtitle: '英超第38轮',
        style: 'dark',
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });

    test('blue style 480p', () async {
      VideoProcessingService.commandLogContext =
          'template_generation_test.dart :: startup blue 480p';
      final outputPath = '${tempDir}startup_blue_480p.mp4';

      final result = await service.generateStartupTemplate(
        outputPath: outputPath,
        title: 'UCL Final',
        subtitle: '欧冠决赛',
        style: 'blue',
        width: 854,
        height: 480,
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');

      final res = await VideoProcessingService.probeResolution(outputPath);
      if (res != null) {
        expect(res.$1, 854);
        expect(res.$2, 480);
      }
    });
  });

  group('generateEndingTemplate', () {
    test('dark style with Chinese text', () async {
      VideoProcessingService.commandLogContext =
          'template_generation_test.dart :: ending dark Chinese';
      final outputPath = '${tempDir}ending_dark.mp4';

      final result = await service.generateEndingTemplate(
        outputPath: outputPath,
        mainText: '感谢观看',
        subText: '点赞关注不迷路',
        style: 'dark',
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });

    test('green style', () async {
      VideoProcessingService.commandLogContext =
          'template_generation_test.dart :: ending green';
      final outputPath = '${tempDir}ending_green.mp4';

      final result = await service.generateEndingTemplate(
        outputPath: outputPath,
        mainText: 'The End',
        subText: 'See you next match!',
        style: 'green',
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });
  });

  group('generateTransitionTemplate', () {
    test('green style', () async {
      VideoProcessingService.commandLogContext =
          'template_generation_test.dart :: transition green';
      final outputPath = '${tempDir}transition_green.mp4';

      final result = await service.generateTransitionTemplate(
        outputPath: outputPath,
        style: 'green',
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });

    test('red style', () async {
      VideoProcessingService.commandLogContext =
          'template_generation_test.dart :: transition red';
      final outputPath = '${tempDir}transition_red.mp4';

      final result = await service.generateTransitionTemplate(
        outputPath: outputPath,
        style: 'red',
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });

    test('blue style', () async {
      VideoProcessingService.commandLogContext =
          'template_generation_test.dart :: transition blue';
      final outputPath = '${tempDir}transition_blue.mp4';

      final result = await service.generateTransitionTemplate(
        outputPath: outputPath,
        style: 'blue',
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });

    test('dark style custom duration', () async {
      VideoProcessingService.commandLogContext =
          'template_generation_test.dart :: transition dark 2s';
      final outputPath = '${tempDir}transition_dark_2s.mp4';

      final result = await service.generateTransitionTemplate(
        outputPath: outputPath,
        style: 'dark',
        durationSecs: 2.0,
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });
  });

  group('embedded templates folder', () {
    test('templates dir is created before any generation', () {
      // Regression: installed (MSIX) builds must resolve a writable
      // templates folder instead of failing on the read-only exe dir.
      final dir = TemplateGeneratorService.templatesDir;
      expect(Directory(dir).existsSync(), isTrue);
      expect(dir.isNotEmpty, isTrue);
    });

    test('ensureFile generates a usable template into templates dir', () async {
      if (ffmpegPath == null) {
        // ensureFile refuses to render without ffmpeg rather than writing a
        // placeholder, so there is nothing to assert in simulation mode.
        return;
      }
      VideoProcessingService.commandLogContext =
          'template_generation_test.dart :: ensureFile ending_dark';
      final gen = TemplateGeneratorService(service);
      final path = await gen.ensureFile(const TemplateSpec(
          'ending_dark.mp4', 'Ending Dark', TemplateCategory.ending));
      final f = File(path);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $path  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });
  });

  group('default bgm resolution', () {
    test('bg_music.mp3 resolves only in the same folder as ffmpeg', () {
      final temp = Directory.systemTemp.createTempSync('hl_bgm_test');
      try {
        File('${temp.path}\\bg_music.mp3').writeAsBytesSync([1, 2, 3]);
        // Sibling of ffmpeg -> found.
        expect(
          VideoProcessingService.resolveDefaultBgmFor(
              '${temp.path}\\ffmpeg.exe'),
          '${temp.path}\\bg_music.mp3',
        );
        // ffmpeg elsewhere -> no bgm.
        expect(
          VideoProcessingService.resolveDefaultBgmFor(
              '${temp.path}\\sub\\ffmpeg.exe'),
          isNull,
        );
        // Empty path -> no bgm.
        expect(VideoProcessingService.resolveDefaultBgmFor(''), isNull);
      } finally {
        temp.deleteSync(recursive: true);
      }
    });
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