// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';

/// Verify the Make pipeline applies the embedded startup template title and
/// the transition template font settings.
void main() {
  late String projectRoot;
  late String tempDir;
  late String startupMp4;
  late String transitionMp4;
  late String sourceMp4;
  late VideoProcessingService service;
  late int runId;

  setUpAll(() async {
    projectRoot = _resolveProjectRoot();
    tempDir = '$projectRoot\\temp\\e2e\\make_pipeline_test\\';
    final dir = Directory(tempDir);
    if (!dir.existsSync()) await dir.create(recursive: true);

    startupMp4 = '$projectRoot\\test\\e2e\\default_templates\\startup.mp4';
    transitionMp4 =
        '$projectRoot\\test\\e2e\\default_templates\\transitionTemplate.mp4';
    sourceMp4 = '$projectRoot\\test\\e2e\\videoSource\\test1.mp4';
    expect(File(startupMp4).existsSync(), isTrue);
    expect(File(transitionMp4).existsSync(), isTrue);
    expect(File(sourceMp4).existsSync(), isTrue);

    VideoProcessingService.commandLogPath = '$projectRoot\\ffmpeg_command';
    // Unique per-run nonce: the log is append-only and shared across runs,
    // so a stable context would match stale entries from previous runs.
    runId = DateTime.now().millisecondsSinceEpoch;

    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    service = VideoProcessingService(ffmpegPath: ffmpegPath);
    print('ffmpeg: ${ffmpegPath ?? "NOT FOUND (simulation mode)"}');
  });

  test('generateTransition applies template font settings', () async {
    VideoProcessingService.commandLogContext =
        'make_pipeline_test.dart :: transition font';
    final out = '${tempDir}trans_font_test.mp4';
    final res = await service.generateTransition(
      outputPath: out,
      text: 'FontTest',
      startupVideoPath: startupMp4,
      transitionTemplatePath: transitionMp4,
      fontSize: 33,
      fontColor: '#00FF00@0.8',
      // Raw Windows path — must be escaped for ffmpeg (regression).
      fontPath: r'C:\Windows\Fonts\msyh.ttc',
    );
    expect(res.exitCode, 0, reason: 'ffmpeg failed:\n${res.stderr}');
    expect(File(out).existsSync(), isTrue);
    expect(File(out).lengthSync(), greaterThan(1000));

    // The ffmpeg command log must carry the template font settings.
    final log = File('$projectRoot\\ffmpeg_command').readAsStringSync();
    expect(log, contains('fontsize=33'));
    expect(log, contains('fontcolor=#00FF00@0.8'));
  });

  test('makeAll overlays the embedded startup title', () async {
    VideoProcessingService.commandLogContext =
        'make_pipeline_test.dart :: makeAll title $runId';
    final outputDir = '${tempDir}title_run\\';
    Directory(outputDir).createSync(recursive: true);

    final startupTemplate = Template(
      id: '',
      name: 'startup.mp4',
      path: startupMp4,
      type: TemplateType.startup,
      title: 'Awesome Highlight',
      fontSize: 48,
      fontColor: '#FFFFFF',
      // Raw Windows path — must be escaped for ffmpeg (regression).
      fontPath: r'C:\Windows\Fonts\msyh.ttc',
    );

    final finalPath = await service.makeAll(
      timeslots: [
        Timeslot(
          id: 'ts1',
          projectId: 'p1',
          videoSourceId: 'v1',
          inPointMs: 12000,
          outPointMs: 22000,
          createdAt: DateTime.now(),
          filename: 'test1.mp4',
          description: 'Slot 1',
        ),
      ],
      startupVideoPath: startupMp4,
      outputDir: outputDir,
      sourcePaths: {'test1.mp4': sourceMp4},
      transitionTemplatePath: transitionMp4,
      startupTemplate: startupTemplate,
    );

    expect(File(finalPath).existsSync(), isTrue, reason: 'final.mp4 missing');
    expect(File(finalPath).lengthSync(), greaterThan(1000));
    // The titled startup clip must have been produced and merged.
    expect(File('${outputDir}startup_titled.mp4').existsSync(), isTrue,
        reason: 'startup_titled.mp4 not generated');
    // At the 720p reference resolution the configured fontSize (48) is
    // applied as-is (no scaling).
    final log = File('$projectRoot\\ffmpeg_command').readAsStringSync();
    final block = _loggedCommandsFor(
        log, 'make_pipeline_test.dart :: makeAll title $runId');
    expect(block, contains('fontsize=48'), reason: '720p startup overlay');
    print('OUTPUT: $finalPath');
  }, timeout: const Timeout(Duration(minutes: 4)));

  test('makeAll scales the startup title fontSize at 4K (regression)',
      () async {
    VideoProcessingService.commandLogContext =
        'make_pipeline_test.dart :: makeAll 4k title $runId';
    final outputDir = '${tempDir}title_run_4k\\';
    Directory(outputDir).createSync(recursive: true);

    final startupTemplate = Template(
      id: '',
      name: 'startup.mp4',
      path: startupMp4,
      type: TemplateType.startup,
      title: 'Awesome Highlight 4K',
      fontSize: 48,
      fontColor: '#FFFFFF',
      fontPath: r'C:\Windows\Fonts\msyh.ttc',
    );

    final finalPath = await service.makeAll(
      timeslots: [
        Timeslot(
          id: 'ts1',
          projectId: 'p1',
          videoSourceId: 'v1',
          inPointMs: 12000,
          outPointMs: 22000,
          createdAt: DateTime.now(),
          filename: 'test1.mp4',
          description: 'Slot 1',
        ),
      ],
      startupVideoPath: startupMp4,
      outputDir: outputDir,
      sourcePaths: {'test1.mp4': sourceMp4},
      transitionTemplatePath: transitionMp4,
      startupTemplate: startupTemplate,
      width: 3840,
      height: 2160,
    );

    expect(File(finalPath).existsSync(), isTrue, reason: 'final.mp4 missing');
    expect(File(finalPath).lengthSync(), greaterThan(1000));
    // The startup overlay must scale the configured size by the target
    // resolution (reference 720p): 48 * 2160/720 = 144. The unscaled 48
    // on a 4K frame renders 3x too small relative to the 720p preview.
    final log = File('$projectRoot\\ffmpeg_command').readAsStringSync();
    final block = _loggedCommandsFor(
        log, 'make_pipeline_test.dart :: makeAll 4k title $runId');
    expect(block, contains('fontsize=144'),
        reason: '4K startup overlay must use the scaled font size');
    expect(block, isNot(contains('fontsize=48')),
        reason: 'unscaled font size leaked into the 4K startup overlay');
    print('OUTPUT: $finalPath');
  }, timeout: const Timeout(Duration(minutes: 8)));

  test('makeAll stamps the slot caption onto the clip bottom-left', () async {
    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    if (ffmpegPath == null) return; // simulation mode has no pixels to measure
    VideoProcessingService.commandLogContext =
        'make_pipeline_test.dart :: caption watermark $runId';

    // Flat black source: then the only near-white pixels in the bottom-left
    // corner are the watermark's glyphs, so the count measures the caption
    // instead of the footage.
    final blank = '${tempDir}blank_source.mp4';
    final mk = await Process.run(ffmpegPath, [
      '-y',
      '-v',
      'error',
      '-f',
      'lavfi',
      '-i',
      'color=c=black:s=1280x720:d=20:r=30',
      '-f',
      'lavfi',
      '-i',
      'anullsrc=r=44100:cl=stereo',
      '-map',
      '0:v',
      '-map',
      '1:a',
      '-t',
      '20',
      '-c:v',
      'libopenh264',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      '64k',
      '-shortest',
      blank,
    ]);
    expect(mk.exitCode, 0,
        reason: 'failed to render the blank source:\n${mk.stderr}');

    final outputDir = '${tempDir}caption_run\\';
    Directory(outputDir).createSync(recursive: true);
    final finalPath = await service.makeAll(
      timeslots: [
        Timeslot(
          id: 'a',
          projectId: 'p',
          videoSourceId: 'v',
          inPointMs: 2000,
          outPointMs: 12000,
          createdAt: DateTime.now(),
          filename: 'blank.mp4',
          description: 'xx助攻xx',
        ),
        Timeslot(
          id: 'b',
          projectId: 'p',
          videoSourceId: 'v',
          inPointMs: 2000,
          outPointMs: 12000,
          createdAt: DateTime.now(),
          filename: 'blank.mp4',
          description: 'xx没收皮球',
        ),
      ],
      startupVideoPath: startupMp4,
      outputDir: outputDir,
      sourcePaths: {'blank.mp4': blank},
      transitionTemplatePath: transitionMp4,
    );
    expect(File(finalPath).existsSync(), isTrue, reason: 'final.mp4 missing');

    // 1) Wiring: the watermark drawtext is in the slice commands, with the
    //    margin and font size scaled for 720p.
    final log = File('$projectRoot\\ffmpeg_command').readAsStringSync();
    final block = _loggedCommandsFor(
        log, 'make_pipeline_test.dart :: caption watermark $runId');
    expect(block, contains('y=h-text_h-28'),
        reason: 'watermark must hug the bottom edge');
    expect(block, contains('fontsize=26'),
        reason: 'watermark must use the 720p reference size');

    // 2) Pixels: the caption really is burned into the bottom-left corner and
    //    not into the top-left one.
    final sub = '${outputDir}slot_0_sub.mp4';
    expect(File(sub).existsSync(), isTrue, reason: 'slot_0_sub.mp4 missing');
    final bottomLeft = await _countWhiteish(ffmpegPath, sub, 16, 640, 480, 70);
    final topLeft = await _countWhiteish(ffmpegPath, sub, 16, 16, 480, 70);
    print('caption pixels: bottom-left=$bottomLeft top-left=$topLeft');
    expect(bottomLeft, greaterThan(300), reason: 'caption glyphs missing');
    expect(bottomLeft, greaterThan(topLeft + 200),
        reason: 'caption must sit in the bottom-left corner');
    print('OUTPUT: $finalPath');
  }, timeout: const Timeout(Duration(minutes: 6)));
}

/// All logged ffmpeg command lines written under `context` (the log is
/// append-only and shared, so callers must use a per-run unique context).
/// Every command of one makeAll call repeats the same context marker, so
/// split into `"[ctx]\ncmd"` entries and join the matching ones.
String _loggedCommandsFor(String log, String context) {
  final parts = log.split(RegExp(r'^\[', multiLine: true));
  return parts.where((p) => p.startsWith('$context]\n')).join();
}

/// Extract one frame from [videoPath], crop the given box, and count pixels
/// whose min RGB channel exceeds [threshold] (near-white). The caption renders
/// white on black, so a corner carrying it shows a clear surplus over an empty
/// corner of the same size.
Future<int> _countWhiteish(
    String ffmpeg, String videoPath, int x, int y, int w, int h,
    {int threshold = 120}) async {
  final rawPath = '$videoPath.$x.$y.raw';
  try {
    final r = await Process.run(ffmpeg, [
      '-y',
      '-v',
      'error',
      '-ss',
      '1.5',
      '-i',
      videoPath,
      '-frames:v',
      '1',
      '-vf',
      'crop=$w:$h:$x:$y',
      '-f',
      'rawvideo',
      '-pix_fmt',
      'rgb24',
      rawPath,
    ]);
    if (r.exitCode != 0) throw StateError('crop failed:\n${r.stderr}');
    final bytes = File(rawPath).readAsBytesSync();
    var count = 0;
    for (var i = 0; i + 2 < bytes.length; i += 3) {
      final mn = bytes[i] < bytes[i + 1]
          ? (bytes[i] < bytes[i + 2] ? bytes[i] : bytes[i + 2])
          : (bytes[i + 1] < bytes[i + 2] ? bytes[i + 1] : bytes[i + 2]);
      if (mn > threshold) count++;
    }
    return count;
  } finally {
    try {
      File(rawPath).deleteSync();
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
