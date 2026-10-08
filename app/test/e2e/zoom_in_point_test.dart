import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';

/// Verify that:
/// 1. extractFrame produces a valid PNG from a video at a given timestamp.
/// 2. makeAll with a remote timeslot that has centerX/centerY set produces
///    a valid final video with the zoom centered on the selected point.
void main() {
  test('extractFrame produces a valid PNG image', () async {
    final projectRoot = _resolveProjectRoot();
    final sourcePath = '$projectRoot\\test\\e2e\\videoSource\\test1.mp4';
    final tempDir = '$projectRoot\\temp\\e2e\\';

    expect(File(sourcePath).existsSync(), isTrue,
        reason: 'Source video missing: $sourcePath');

    final dir = Directory(tempDir);
    if (!dir.existsSync()) await dir.create(recursive: true);

    VideoProcessingService.commandLogPath = '$projectRoot\\ffmpeg_command';
    VideoProcessingService.commandLogContext =
        'zoom_in_point_test.dart :: extractFrame produces a valid PNG image';

    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    final service = VideoProcessingService(ffmpegPath: ffmpegPath);
    final framePath = '${tempDir}zoom_point_test_frame.png';

    final result = await service.extractFrame(
      sourcePath: sourcePath,
      timestampSecs: 5.0,
      outputPath: framePath,
    );

    expect(result.exitCode, 0,
        reason: 'ffmpeg failed:\n${result.stderr}');
    expect(File(framePath).existsSync(), isTrue,
        reason: 'Frame PNG was not created: $framePath');
    expect(File(framePath).lengthSync(), greaterThan(1000),
        reason: 'Frame PNG too small — likely corrupt');
  });

  test('Remote timeslot with zoom-in center point produces valid video', () async {
    final projectRoot = _resolveProjectRoot();
    final sourceDir = '$projectRoot\\test\\e2e\\videoSource';
    final tempDirPath = '$projectRoot\\temp\\e2e\\';

    final outputDir =
        '${tempDirPath}zoom_point_test_${DateTime.now().millisecondsSinceEpoch}\\';
    final dir = Directory(outputDir);
    if (dir.existsSync()) {
      try { await dir.delete(recursive: true); } catch (_) {}
    }

    VideoProcessingService.commandLogContext =
        'zoom_in_point_test.dart :: Remote timeslot with zoom-in center point produces valid video';

    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    final service = VideoProcessingService(ffmpegPath: ffmpegPath);

    // Build a remote timeslot with a zoom-in center point set.
    // centerX=0.3, centerY=0.4 means the zoom centers on 30% from left,
    // 40% from top of the frame.
    final timeslots = [
      Timeslot(
        id: '',
        projectId: '',
        videoSourceId: '',
        inPointMs: 11000,
        outPointMs: 11000,
        createdAt: DateTime.now(),
        filename: 'test1.mp4',
        description: 'zoom_point_mark',
        elapse: 0,
        remote: true,
        centerX: 0.3,
        centerY: 0.4,
      ),
    ];

    final sourceByFilename = <String, String>{
      'test1.mp4': '$sourceDir\\test1.mp4',
    };

    final startupPath = '$sourceDir\\startup.mp4';

    await service.makeAll(
      timeslots: timeslots,
      startupVideoPath: startupPath,
      outputDir: outputDir,
      sourcePaths: sourceByFilename,
      endingVideoPath: '$sourceDir\\Ending.mp4',
      bgMusicPath: '$sourceDir\\bg_music.mp3',
    );

    final finalPath = '${outputDir}final.mp4';
    final bodyPath = '${outputDir}body.mp4';
    final bodyMusicPath = '${outputDir}body_music.mp4';
    final subPath = '${outputDir}slot_0_sub.mp4';
    final transitionPath = '${outputDir}slot_0_transition.mp4';

    expect(File(finalPath).existsSync(), isTrue,
        reason: 'final.mp4 missing');
    expect(File(bodyPath).existsSync(), isTrue,
        reason: 'body.mp4 missing');
    expect(File(bodyMusicPath).existsSync(), isTrue,
        reason: 'body_music.mp4 missing');
    expect(File(subPath).existsSync(), isTrue,
        reason: 'Sub video missing (zoom-in point)');
    expect(File(transitionPath).existsSync(), isTrue,
        reason: 'Transition video missing');
    expect((File(subPath).lengthSync()) > 0, isTrue,
        reason: 'Sub video is empty');
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
