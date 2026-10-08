// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';

/// Verify every transition template variant (dark + light palettes) reserves
/// a center text zone, and that the original real-video transition
/// (app/windows/res/transition.mp4) gets a reserved zone via the drawbox in
/// generateTransition.  Outputs land in temp/template_gen/.
void main() {
  late String projectRoot;
  late String tempDir;
  late String realTransition;
  late VideoProcessingService service;

  setUpAll(() async {
    projectRoot = _resolveProjectRoot();
    tempDir = '$projectRoot\\temp\\e2e\\template_gen\\';
    final dir = Directory(tempDir);
    if (!dir.existsSync()) await dir.create(recursive: true);
    realTransition = '$projectRoot\\app\\windows\\res\\transition.mp4';

    VideoProcessingService.commandLogPath = '$projectRoot\\ffmpeg_command';

    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    service = VideoProcessingService(ffmpegPath: ffmpegPath);
    print('ffmpeg: ${ffmpegPath ?? "NOT FOUND (simulation mode)"}');
  });

  // (variant, style).  Dark variants use dark styles; the five light
  // variants use light styles.  Every variant is wrapped in the shared
  // center text zone by _transitionLum.
  const variants = <(String, String)>[
    ('classic', 'green'),
    ('chevrons', 'blue'),
    ('sweep', 'dark'),
    ('pulse', 'red'),
    ('grid', 'green'),
    ('rays', 'blue'),
    ('diamonds', 'dark'),
    ('waves', 'red'),
    ('spotlights', 'green'),
    ('crosshatch', 'blue'),
    ('orbit', 'dark'),
    ('shutter', 'red'),
    ('scan', 'green'),
    ('ripple', 'blue'),
    ('linen', 'linen'),
    ('sunburst', 'cream'),
    ('polka', 'blush'),
    ('arcs', 'sky'),
    ('zigzag', 'mint'),
  ];

  for (final v in variants) {
    final variant = v.$1;
    final style = v.$2;

    test('$variant reserves center text zone', () async {
      VideoProcessingService.commandLogContext =
          'transition_variants_test.dart :: $variant';
      final outputPath = '${tempDir}transition_$variant.mp4';

      final result = await service.generateTransitionTemplate(
        outputPath: outputPath,
        style: style,
        variant: variant,
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });

    test('$variant with centered text overlay', () async {
      VideoProcessingService.commandLogContext =
          'transition_variants_test.dart :: $variant + text';
      final templatePath = '${tempDir}transition_$variant.mp4';
      final outputPath = '${tempDir}transition_${variant}_text.mp4';

      expect(File(templatePath).existsSync(), isTrue,
          reason: 'run the template test first');

      final result = await service.generateTransition(
        outputPath: outputPath,
        text: '上半场 · 精彩进球',
        startupVideoPath: templatePath,
        transitionTemplatePath: templatePath,
      );

      expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
      final f = File(outputPath);
      expect(f.existsSync(), isTrue);
      expect(f.lengthSync(), greaterThan(1000));
      print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
    });
  }

  test('original real-video transition gets reserved text zone', () async {
    VideoProcessingService.commandLogContext =
        'transition_variants_test.dart :: real res/transition.mp4 + text';
    final outputPath = '${tempDir}transition_real_text.mp4';

    expect(File(realTransition).existsSync(), isTrue,
        reason: 'default transition template missing');

    final result = await service.generateTransition(
      outputPath: outputPath,
      text: '下半场 · 绝杀时刻',
      startupVideoPath: realTransition,
      transitionTemplatePath: realTransition,
    );

    expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
    final f = File(outputPath);
    expect(f.existsSync(), isTrue);
    expect(f.lengthSync(), greaterThan(1000));
    print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
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
