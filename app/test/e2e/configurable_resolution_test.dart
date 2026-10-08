// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';

/// Verify that:
/// 1. probeResolution returns valid dimensions for a known test video.
/// 2. generateTransition with a custom resolution produces valid output.
/// 3. makeAll with a custom resolution (480P) produces valid output
///    whose probed resolution matches the requested dimensions.
void main() {
  test('probeResolution returns dimensions for test1.mp4', () async {
    final projectRoot = _resolveProjectRoot();
    final sourcePath = '$projectRoot\\test\\e2e\\videoSource\\test1.mp4';

    expect(File(sourcePath).existsSync(), isTrue,
        reason: 'Source video missing: $sourcePath');

    final res = await VideoProcessingService.probeResolution(sourcePath);
    expect(res, isNotNull, reason: 'probeResolution returned null');
    expect(res!.$1, greaterThan(0), reason: 'width should be >0');
    expect(res.$2, greaterThan(0), reason: 'height should be >0');
    print('probed resolution: ${res.$1}x${res.$2}');
  });

  test('generateTransition with 480P resolution produces valid output', () async {
    final projectRoot = _resolveProjectRoot();
    final templatePath = '$projectRoot\\app\\windows\\res\\transition.mp4';
    final tempDir = '$projectRoot\\temp\\e2e\\';

    expect(File(templatePath).existsSync(), isTrue,
        reason: 'Template file missing: $templatePath');

    final dir = Directory(tempDir);
    if (!dir.existsSync()) await dir.create(recursive: true);

    VideoProcessingService.commandLogPath = '$projectRoot\\ffmpeg_command';
    VideoProcessingService.commandLogContext =
        'configurable_resolution_test.dart :: '
        'generateTransition with 480P resolution';

    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    final service = VideoProcessingService(ffmpegPath: ffmpegPath);
    final outputPath = '${tempDir}resolution_480p_transition.mp4';

    final result = await service.generateTransition(
      outputPath: outputPath,
      text: '480P test',
      startupVideoPath: '$projectRoot\\test\\e2e\\videoSource\\test1.mp4',
      transitionTemplatePath: templatePath,
      width: 854,
      height: 480,
    );

    expect(result.exitCode, 0,
        reason: 'ffmpeg failed:\n${result.stderr}');

    final outFile = File(outputPath);
    expect(outFile.existsSync(), isTrue,
        reason: 'Output file was not created: $outputPath');
    expect(outFile.lengthSync(), greaterThan(1000),
        reason: 'Output file too small');

    // Verify output resolution matches target.
    final res = await VideoProcessingService.probeResolution(outputPath);
    if (res != null) {
      expect(res.$1, 854, reason: 'expected width 854 but got ${res.$1}');
      expect(res.$2, 480, reason: 'expected height 480 but got ${res.$2}');
    }
  });

  test('makeAll with 480P resolution produces final.mp4 at 854x480', () async {
    final projectRoot = _resolveProjectRoot();
    final sourceDir = '$projectRoot\\test\\e2e\\videoSource';
    final tempDirPath = '$projectRoot\\temp\\e2e\\';

    final outputDir =
        '${tempDirPath}resolution_480p_${DateTime.now().millisecondsSinceEpoch}\\';
    final dir = Directory(outputDir);
    if (dir.existsSync()) {
      try { await dir.delete(recursive: true); } catch (_) {}
    }

    VideoProcessingService.commandLogContext =
        'configurable_resolution_test.dart :: '
        'makeAll with 480P resolution';

    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    final service = VideoProcessingService(ffmpegPath: ffmpegPath);

    final timeslots = [
      Timeslot(
        id: '',
        projectId: '',
        videoSourceId: '',
        inPointMs: 8000,
        outPointMs: 8000,
        createdAt: DateTime.now(),
        filename: 'test1.mp4',
        description: 'resolution_test_mark',
        elapse: 0,
        remote: false,
      ),
    ];

    final sourceByFilename = <String, String>{
      'test1.mp4': '$sourceDir\\test1.mp4',
    };

    final startupPath = '$sourceDir\\test1.mp4';

    await service.makeAll(
      timeslots: timeslots,
      startupVideoPath: startupPath,
      outputDir: outputDir,
      sourcePaths: sourceByFilename,
      width: 854,
      height: 480,
    );

    final finalPath = '${outputDir}final.mp4';
    expect(File(finalPath).existsSync(), isTrue,
        reason: 'final.mp4 missing');
    expect((File(finalPath).lengthSync()) > 0, isTrue,
        reason: 'final.mp4 is empty');

    // Verify output resolution matches target.
    final res = await VideoProcessingService.probeResolution(finalPath);
    if (res != null) {
      expect(res.$1, 854, reason: 'expected final width 854 but got ${res.$1}');
      expect(res.$2, 480, reason: 'expected final height 480 but got ${res.$2}');
    }
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
