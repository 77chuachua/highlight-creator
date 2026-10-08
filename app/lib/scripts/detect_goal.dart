// Find the goal in test/e2e/videoSource/test1.mp4 and mark it on a frame.
// Run with: dart run lib/scripts/detect_goal.dart
import 'dart:io';

import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/services/goal_detection_service.dart';

Future<void> main() async {
  final ffmpeg = await VideoProcessingService.findFfmpeg();
  if (ffmpeg == null) {
    stderr.writeln('ffmpeg not found');
    exit(1);
  }

  var dir = Directory.current;
  while (!File('${dir.path}\\test\\e2e\\videoSource\\test1.mp4')
      .existsSync()) {
    if (dir.parent.path == dir.path) {
      stderr.writeln('test/e2e/videoSource/test1.mp4 not found');
      exit(1);
    }
    dir = dir.parent;
  }
  final video = '${dir.path}\\test\\e2e\\videoSource\\test1.mp4';
  final outDir = '${dir.path}\\temp\\goal_detection';

  final svc = GoalDetectionService(ffmpegPath: ffmpeg);
  final res = await svc.detectGoal(videoPath: video, outputDir: outDir);

  stdout.writeln('frame:  ${res.framePath}');
  stdout.writeln('marked: ${res.markedPath}');
  stdout.writeln('json:   ${res.jsonPath}');
  for (final g in res.goals) {
    stdout.writeln(
        'goal @ x=${g.x} y=${g.y} w=${g.w} h=${g.h} score=${g.score.toStringAsFixed(0)}');
  }
  if (res.goals.isEmpty) stdout.writeln('no goal detected');
}
