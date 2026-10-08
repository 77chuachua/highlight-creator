// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/services/template_generator_service.dart';

/// Verify the built-in design sets ('blue' sky theme, 'yellow' sun theme,
/// 'green' forest theme, 'nocturne' night-stadium theme): each set ships
/// startup + ending + transition, the built-in list carries exactly one
/// transition per set, and every set part renders playable 720p video locally.
void main() {
  late String projectRoot;
  late String tempDir;
  late VideoProcessingService service;
  late String? ffmpegPath;

  setUpAll(() async {
    projectRoot = _resolveProjectRoot();
    tempDir = '$projectRoot\\temp\\e2e\\design_sets\\';
    final dir = Directory(tempDir);
    if (!dir.existsSync()) await dir.create(recursive: true);

    VideoProcessingService.commandLogPath = '$projectRoot\\ffmpeg_command';

    ffmpegPath = await VideoProcessingService.findFfmpeg();
    service = VideoProcessingService(ffmpegPath: ffmpegPath);
    print('ffmpeg: ${ffmpegPath ?? "NOT FOUND (simulation mode)"}');
  });

  group('built-in template structure', () {
    test('transitions are exactly one per design set', () {
      final transitions = TemplateGeneratorService.allSpecs
          .where((s) => s.category == TemplateCategory.transition)
          .toList();
      expect(transitions.length, TemplateGeneratorService.allSets.length,
          reason: 'one transition per design set; legacy ones removed');
      expect(transitions.map((s) => s.fileName).toSet(), {
        'transition_blue.mp4',
        'transition_yellow.mp4',
        'transition_green.mp4',
        'transition_nocturne.mp4',
      });
    });

    test('every design set has startup + ending + transition in allSpecs', () {
      expect(TemplateGeneratorService.allSets.map((s) => s.id),
          containsAll(['blue', 'yellow', 'green', 'nocturne']));
      for (final set in TemplateGeneratorService.allSets) {
        expect(set.startup.category, TemplateCategory.startup,
            reason: '${set.id} startup category');
        expect(set.ending.category, TemplateCategory.ending,
            reason: '${set.id} ending category');
        expect(set.transition.category, TemplateCategory.transition,
            reason: '${set.id} transition category');
        for (final spec in set.specs) {
          expect(TemplateGeneratorService.allSpecs.contains(spec), isTrue,
              reason: '${spec.fileName} missing from allSpecs');
        }
      }
    });

    test('only the design-set templates remain embedded', () {
      // issues.md: the config dialog keeps only the built-in sets; all legacy
      // startup_1..3 / transition_classic / ending_dark templates are gone.
      const specs = TemplateGeneratorService.allSpecs;
      expect(specs.length, TemplateGeneratorService.allSets.length * 3);
      expect(specs.any((s) => s.fileName.contains('startup_1')), isFalse);
      expect(specs.any((s) => s.fileName.contains('transition_classic')), isFalse);
      expect(specs.any((s) => s.fileName.contains('ending_dark')), isFalse);
    });

    test('ensureFile reports real progress while generating', () async {
      if (ffmpegPath == null) return; // simulation mode has no real render
      VideoProcessingService.commandLogContext =
          'design_sets_test.dart :: ensureFile progress';
      final gen = TemplateGeneratorService(service);
      final spec = TemplateGeneratorService.allSpecs
          .firstWhere((s) => s.category == TemplateCategory.startup);
      // Remove any pre-generated copy so the render actually runs.
      final dir = TemplateGeneratorService.templatesDir;
      final path = '$dir${Platform.pathSeparator}${spec.fileName}';
      if (File(path).existsSync()) File(path).deleteSync();

      final progress = <double>[];
      await gen.ensureFile(spec, onProgress: progress.add);
      expect(progress, isNotEmpty, reason: 'no progress reported');
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1]),
            reason: 'progress must be monotonic');
      }
      expect(progress.last, greaterThanOrEqualTo(0.9),
          reason: 'progress should reach ~100%');
      print('ensureFile progress samples: ${progress.length}');
    }, timeout: const Timeout(Duration(seconds: 300)));

    test('ensureFile serves an already-generated template without ffmpeg',
        () async {
      // ensureFile refuses to render when ffmpeg is missing rather than
      // writing a placeholder — but a template generated earlier must stay
      // usable on a machine that later loses ffmpeg. This pins the guard
      // *after* the cache check, where it belongs.
      final dir = TemplateGeneratorService.templatesDir;
      const name = '_ensurefile_cached_probe.mp4';
      final path = '$dir${Platform.pathSeparator}$name';
      File(path).writeAsBytesSync(List<int>.filled(2048, 0));
      final gen = TemplateGeneratorService(service);
      const spec =
          TemplateSpec(name, 'Cached Probe', TemplateCategory.ending);
      try {
        expect(await gen.ensureFile(spec), path,
            reason: 'cached template must resolve without invoking ffmpeg');
      } finally {
        try {
          File(path).deleteSync();
        } catch (_) {}
      }
    });

    test('missing-ffmpeg error reads as a sentence, not a Dart error', () {
      // The message is shown verbatim in the template editor's error slot.
      const why = '找不到 ffmpeg.exe';
      final e = TemplateGenerationUnavailable(why);
      expect(e.toString(), why);
      expect(e.toString(), isNot(contains('Bad state')));
      expect(e, isA<Exception>());
    });
  });

  for (final set in const [
    ('blue', 'skyblue'),
    ('yellow', 'gold'),
    ('green', 'forest'),
    ('nocturne', 'nocturne'),
  ]) {
    final setId = set.$1;
    final style = set.$2;
    // Yellow carries 12 rotating rays and nocturne 3 ray-cast light shafts;
    // both need longer than the two-layer sets.
    final timeoutSecs = (setId == 'yellow' || setId == 'nocturne') ? 600 : 120;

    group('$setId set generation', () {
      test('$setId startup renders 720p video', () async {
        VideoProcessingService.commandLogContext =
            'design_sets_test.dart :: $setId startup';
        final outputPath = '${tempDir}startup_$setId.mp4';

        final result = await service.generateSetStartup(
          outputPath: outputPath,
          set: setId,
        );

        expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
        final f = File(outputPath);
        expect(f.existsSync(), isTrue);
        expect(f.lengthSync(), greaterThan(1000));
        final res = await VideoProcessingService.probeResolution(outputPath);
        if (res != null) {
          expect(res.$1, 1280);
          expect(res.$2, 720);
        }
        print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');
      }, timeout: Timeout(Duration(seconds: timeoutSecs)));

      test('$setId ending renders 720p video', () async {
        VideoProcessingService.commandLogContext =
            'design_sets_test.dart :: $setId ending';
        final outputPath = '${tempDir}ending_$setId.mp4';

        final result = await service.generateSetEnding(
          outputPath: outputPath,
          set: setId,
        );

        expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
        final f = File(outputPath);
        expect(f.existsSync(), isTrue);
        expect(f.lengthSync(), greaterThan(1000));
        final res = await VideoProcessingService.probeResolution(outputPath);
        if (res != null) {
          expect(res.$1, 1280);
          expect(res.$2, 720);
        }
        print('OUTPUT: $outputPath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');

        if (ffmpegPath != null) {
          // Brand watermark "Highlight Creator" sits in the bottom-right
          // corner as white text. Count white-ish pixels (min RGB > 120)
          // in that corner vs the mirrored bottom-left corner at t=1.5:
          // the watermark must add a clear surplus of white-ish pixels.
          final right = await _countWhiteish(
              ffmpegPath!, outputPath, 1040, 656, 200, 34);
          final left = await _countWhiteish(
              ffmpegPath!, outputPath, 40, 656, 200, 34);
          print('watermark check right=$right left=$left');
          expect(right, greaterThan(left + 200),
              reason: 'bottom-right watermark missing or too faint');
        }
      }, timeout: Timeout(Duration(seconds: timeoutSecs)));

      test('$setId transition renders and supports centered text', () async {
        VideoProcessingService.commandLogContext =
            'design_sets_test.dart :: $setId transition';
        final templatePath = '${tempDir}transition_$setId.mp4';

        final result = await service.generateTransitionTemplate(
          outputPath: templatePath,
          variant: setId,
          style: style,
        );

        expect(result.exitCode, 0, reason: 'ffmpeg failed:\n${result.stderr}');
        final f = File(templatePath);
        expect(f.existsSync(), isTrue);
        expect(f.lengthSync(), greaterThan(1000));
        print('OUTPUT: $templatePath  (${(f.lengthSync() / 1024).toStringAsFixed(1)} KB)');

        final outputPath = '${tempDir}transition_${setId}_text.mp4';
        final overlay = await service.generateTransition(
          outputPath: outputPath,
          text: '精彩瞬间',
          startupVideoPath: templatePath,
          transitionTemplatePath: templatePath,
        );
        expect(overlay.exitCode, 0,
            reason: 'ffmpeg failed:\n${overlay.stderr}');
        expect(File(outputPath).lengthSync(), greaterThan(1000));
        print('OUTPUT: $outputPath  (${(File(outputPath).lengthSync() / 1024).toStringAsFixed(1)} KB)');
      });
    });
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

/// Extract one frame at 1.5 s, crop the given box, and count pixels whose
/// min RGB channel exceeds [threshold] (i.e. white-ish). The watermark text
/// renders as near-white glyphs, so its corner must show a clear surplus
/// over the mirrored background-only corner.
Future<int> _countWhiteish(String ffmpeg, String videoPath, int x, int y,
    int w, int h, {int threshold = 120}) async {
  final rawPath = '$videoPath.$x.$y.raw';
  try {
    final r = await Process.run(ffmpeg, [
      '-y',
      '-v', 'error',
      '-ss', '1.5',
      '-i', videoPath,
      '-frames:v', '1',
      '-vf', 'crop=$w:$h:$x:$y',
      '-f', 'rawvideo',
      '-pix_fmt', 'rgb24',
      rawPath,
    ]);
    if (r.exitCode != 0) throw StateError('crop failed:\n${r.stderr}');
    final bytes = File(rawPath).readAsBytesSync();
    var count = 0;
    for (var i = 0; i < bytes.length; i += 3) {
      final mn = bytes[i] < bytes[i + 1]
          ? (bytes[i] < bytes[i + 2] ? bytes[i] : bytes[i + 2])
          : (bytes[i + 1] < bytes[i + 2] ? bytes[i + 1] : bytes[i + 2]);
      if (mn > threshold) count++;
    }
    return count;
  } finally {
    try { File(rawPath).deleteSync(); } catch (_) {}
  }
}
