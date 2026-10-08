import 'dart:io' show Directory, File;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/data/repositories/timeslot_repository_impl.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';

// ---------------------------------------------------------------------------
// Path helpers (mirrors the logic from use_case_test.dart)
// ---------------------------------------------------------------------------
String _resolveVideoSourceDir() {
  final cwd = Directory.current.path;
  if (cwd.endsWith('app')) {
    return '${Directory.current.parent.path}\\test\\e2e\\videoSource';
  }
  return '$cwd\\test\\e2e\\videoSource';
}

String _resolveTempDir() {
  final cwd = Directory.current.path;
  if (cwd.endsWith('app')) {
    return '${Directory.current.parent.path}\\temp\\e2e\\';
  }
  return '$cwd\\temp\\e2e\\';
}

/// Helper: add a video source to the current project through the ViewModel
/// (setup-only operation — file picking cannot be driven via tester.tap).
Future<void> _addSource(
    ProviderContainer container, String projectId, String filePath) async {
  await container.read(recordProvider.notifier).addVideoSource(
        projectId,
        VideoSource(
          id: '',
          projectId: projectId,
          filePath: filePath,
          durationMs: 0,
          width: 0,
          height: 0,
          codecName: '',
          fps: 0,
          createdAt: DateTime.now(),
        ),
      );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  setUpAll(() {
    // Enable ffmpeg command logging (project root, survives temp cleanup).
    VideoProcessingService.commandLogPath =
        '${Directory(_resolveTempDir()).parent.path}\\ffmpeg_command';
  });

  // ────────────────────────────────────────────────────────────────
  // Remote effect — smooth zoom 100%→170% + x-pan 0→500
  // ────────────────────────────────────────────────────────────────
  test('Remote timeslot applies smooth zoom-pan effect to sub video', () async {
    final projectRepo = ProjectRepositoryImpl();
    final timeslotRepo = TimeslotRepositoryImpl();
    final sourceDir = _resolveVideoSourceDir();
    final tempDirPath = _resolveTempDir();

    // Use a dedicated subdirectory so we don't interfere with other tests.
    // Append a timestamp to avoid file-lock conflicts with parallel test runs.
    final outputDir =
        '${tempDirPath}remote_test_${DateTime.now().millisecondsSinceEpoch}\\';
    final dir = Directory(outputDir);
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
      } catch (_) {
        /* locked by prior run */
      }
    }

    final container = ProviderContainer(
      overrides: [
        projectRepositoryProvider.overrideWith((ref) => projectRepo),
        timeslotRepositoryProvider.overrideWith((ref) => timeslotRepo),
      ],
    );
    addTearDown(container.dispose);

    final recVm = container.read(recordProvider.notifier);
    RecordState readState() => container.read(recordProvider);

    // Setup: create project and add one source.
    await recVm.createProject('Remote Test');
    final pid = readState().selectedProjectId!;
    await _addSource(container, pid, '$sourceDir\\test1.mp4');

    // Mark a timeslot with remote: true.
    final project = readState().selectedProject!;
    await recVm.mark(
      videoSourceId: project.sources[0].id,
      positionMs: 11000,
      filename: 'test1.mp4',
      description: 'remote_mark',
      remote: true,
    );

    expect(readState().timeslots.length, 1);
    expect(readState().timeslots[0].remote, isTrue);
    expect(readState().timeslots[0].description, 'remote_mark');

    // Run make pipeline.
    final startupPath = '$sourceDir\\startup.mp4';
    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    final service = VideoProcessingService(ffmpegPath: ffmpegPath);

    final sourceByFilename = <String, String>{
      'test1.mp4': '$sourceDir\\test1.mp4',
    };

    // Annotate log entries for this test.
    VideoProcessingService.commandLogContext =
        'remote_effect_test.dart :: Remote timeslot applies smooth zoom-pan effect to sub video';

    await service.makeAll(
      timeslots: readState().timeslots,
      startupVideoPath: startupPath,
      outputDir: outputDir,
      sourcePaths: sourceByFilename,
      endingVideoPath: '$sourceDir\\Ending.mp4',
      bgMusicPath: '$sourceDir\\bg_music.mp3',
    );

    // Verify outputs exist.
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
        reason: 'Sub video missing (remote effect)');
    expect(File(transitionPath).existsSync(), isTrue,
        reason: 'Transition video missing');
    expect((File(subPath).lengthSync()) > 0, isTrue,
        reason: 'Sub video is empty');
  });
}
