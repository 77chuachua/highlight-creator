import 'dart:io' show Directory, File, Platform;

import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';

class TemplateSpec {
  final String fileName;
  final String label;
  final TemplateCategory category;

  const TemplateSpec(this.fileName, this.label, this.category);
}

enum TemplateCategory { startup, transition, ending }

/// Thrown when a template cannot be rendered at all because ffmpeg is missing.
///
/// Its own type rather than a plain StateError because the message goes
/// straight into the template editor's error slot, which shows `toString()`
/// verbatim — "Bad state: ..." would leak Dart vocabulary into the UI.
class TemplateGenerationUnavailable implements Exception {
  final String reason;

  TemplateGenerationUnavailable(this.reason);

  @override
  String toString() => reason;
}

/// A cohesive design set: one startup intro, one ending, and one transition
/// that share a theme (colors + pattern language). New sets are added here and
/// their specs surface in [TemplateGeneratorService.allSpecs] automatically.
class DesignSet {
  final String id;
  final String label;
  final TemplateSpec startup;
  final TemplateSpec ending;
  final TemplateSpec transition;

  const DesignSet(this.id, this.label, this.startup, this.ending, this.transition);

  List<TemplateSpec> get specs => [startup, ending, transition];
}

class TemplateGeneratorService {
  final VideoProcessingService _service;

  TemplateGeneratorService(this._service);

  static String? _templatesDirCache;

  /// Directory where embedded template videos are stored.
  ///
  /// Lives under %USERPROFILE%\HighlightCreator\templates so it is writable
  /// for every install layout (dev, zip, installer, MSIX). The folder is
  /// created before any video is generated.
  static String get templatesDir {
    if (_templatesDirCache != null) return _templatesDirCache!;
    final dir = AppPaths.templatesDir;
    Directory(dir).createSync(recursive: true);
    _templatesDirCache = dir;
    return dir;
  }

  // Blue design set spec files (referenced by both allSets and allSpecs).
  static const _blueStartup =
      TemplateSpec('startup_blue.mp4', 'Startup Blue', TemplateCategory.startup);
  static const _blueEnding =
      TemplateSpec('ending_blue.mp4', 'Ending Blue', TemplateCategory.ending);
  static const _blueTransition =
      TemplateSpec('transition_blue.mp4', 'Transition Blue', TemplateCategory.transition);

  // Yellow design set spec files (bright sun-yellow theme).
  static const _yellowStartup = TemplateSpec(
      'startup_yellow.mp4', 'Startup Yellow', TemplateCategory.startup);
  static const _yellowEnding = TemplateSpec(
      'ending_yellow.mp4', 'Ending Yellow', TemplateCategory.ending);
  static const _yellowTransition = TemplateSpec('transition_yellow.mp4',
      'Transition Yellow', TemplateCategory.transition);

  // Green design set spec files (forest-green theme).
  static const _greenStartup = TemplateSpec(
      'startup_green.mp4', 'Startup Green', TemplateCategory.startup);
  static const _greenEnding = TemplateSpec(
      'ending_green_theme.mp4', 'Ending Green Theme', TemplateCategory.ending);
  static const _greenTransition = TemplateSpec('transition_green.mp4',
      'Transition Green', TemplateCategory.transition);

  // Nocturne design set (night stadium: raking light shafts, mowed pitch).
  static const _nocturneStartup = TemplateSpec(
      'startup_nocturne.mp4', 'Startup Nocturne', TemplateCategory.startup);
  static const _nocturneEnding = TemplateSpec('ending_nocturne.mp4',
      'Ending Nocturne', TemplateCategory.ending);
  static const _nocturneTransition = TemplateSpec('transition_nocturne.mp4',
      'Transition Nocturne', TemplateCategory.transition);

  /// The built-in brand sets. 'blue' = sky-blue theme with drifting dots;
  /// 'yellow' = sun-yellow theme with rotating rays;
  /// 'green' = forest-green theme with floating leaves;
  /// 'nocturne' = night stadium built in depth (raking light shafts, mowed
  /// pitch, anamorphic streak) rather than from a repeating pattern. Each set
  /// carries its own intro / ending / transition sharing one visual language.
  static const List<DesignSet> allSets = [
    DesignSet('blue', 'Blue', _blueStartup, _blueEnding, _blueTransition),
    DesignSet('yellow', 'Yellow', _yellowStartup, _yellowEnding,
        _yellowTransition),
    DesignSet('green', 'Green', _greenStartup, _greenEnding,
        _greenTransition),
    DesignSet('nocturne', 'Nocturne', _nocturneStartup, _nocturneEnding,
        _nocturneTransition),
  ];

  static const List<TemplateSpec> allSpecs = [
    _blueStartup,
    _blueEnding,
    _blueTransition,
    _yellowStartup,
    _yellowEnding,
    _yellowTransition,
    _greenStartup,
    _greenEnding,
    _greenTransition,
    _nocturneStartup,
    _nocturneEnding,
    _nocturneTransition,
  ];

  static const _transitionStyles = <String, String>{
    'classic': 'green',
    'sweep': 'dark',
    'blue': 'skyblue',
    'yellow': 'gold',
    'green': 'forest',
    'nocturne': 'nocturne',
  };

  List<TemplateSpec> missingSpecs() {
    final dir = templatesDir;
    return allSpecs.where((s) {
      return !File('$dir${Platform.pathSeparator}${s.fileName}').existsSync();
    }).toList();
  }

  /// Resolve ffmpeg, or stop with something the user can act on.
  ///
  /// Every generator in [VideoProcessingService] falls through to its
  /// `_simulateCopy` path when ffmpeg is missing, which quietly writes a
  /// placeholder MP4 that is indistinguishable from a successful render — the
  /// user gets a blank template and a success message, and nothing in the
  /// output file explains why. A missing decoder is the one failure worth
  /// stopping for, so it is checked once up front rather than after the fact.
  static Future<void> _requireFfmpeg() async {
    if (await VideoProcessingService.isFfmpegAvailable()) return;
    throw TemplateGenerationUnavailable(
      '找不到 ffmpeg.exe，无法生成模板 / ffmpeg.exe not found, cannot generate '
      'templates.\n'
      'Highlight Creator 用 ffmpeg 渲染所有模板；没有它只会得到一个空占位文件。\n'
      'Fix: place ffmpeg.exe next to highlight_creator.exe, or anywhere on '
      'PATH, or in C:\\ffmpeg\\bin (see VideoProcessingService.findFfmpeg).',
    );
  }

  /// Return the on-disk path for [spec], generating it first when missing.
  Future<String> ensureFile(
    TemplateSpec spec, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = templatesDir;
    Directory(dir).createSync(recursive: true);
    final path = '$dir${Platform.pathSeparator}${spec.fileName}';
    if (!File(path).existsSync()) {
      await _requireFfmpeg();
      await _generateOne(spec, path, onProgress: onProgress);
    }
    return path;
  }

  Future<List<TemplateSpec>> generateAll({
    required void Function(int done, int total, TemplateSpec current) onProgress,
  }) async {
    final dir = templatesDir;
    Directory(dir).createSync(recursive: true);

    final missing = missingSpecs();
    if (missing.isEmpty) return <TemplateSpec>[];
    // One check for the whole batch: findFfmpeg spawns `where`, so asking per
    // spec would pay for it twelve times.
    await _requireFfmpeg();

    final total = missing.length;
    final generated = <TemplateSpec>[];

    for (var i = 0; i < total; i++) {
      final spec = missing[i];
      onProgress(i, total, spec);
      final outPath = '$dir${Platform.pathSeparator}${spec.fileName}';
      await _generateOne(spec, outPath);
      generated.add(spec);
    }

    onProgress(total, total, missing.isNotEmpty ? missing.last : allSpecs.first);
    return generated;
  }

  /// Resolve a default background music file for ending templates.
  static String? _resolveEndingBgm() {
    // 1. Packaged release layout: audio shipped beside the executable.
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      for (final name in ['Ending.mp4']) {
        final p = '$exeDir${Platform.pathSeparator}$name';
        if (File(p).existsSync()) return p;
      }
    } catch (_) {}

    // 2. Dev layout: walk up from cwd to find the project root.
    // Walk up from cwd to find the project root, then check known paths.
    var dir = Directory.current;
    while (true) {
      for (final candidate in [
        r'temp\ending_normalized.mp4',
        r'test\e2e\default_templates\Ending.mp4',
      ]) {
        final p = '$dir${Platform.pathSeparator}$candidate';
        if (File(p).existsSync()) return p;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return null;
  }

  /// The design set [spec] belongs to (matched by file name), or null for
  /// legacy football / dark / green specs.
  static DesignSet? _setFor(TemplateSpec spec) {
    for (final s in allSets) {
      if (s.specs.any((x) => x.fileName == spec.fileName)) return s;
    }
    return null;
  }

  Future<void> _generateOne(
    TemplateSpec spec,
    String outPath, {
    void Function(double progress)? onProgress,
  }) async {
    final set = _setFor(spec);
    switch (spec.category) {
      case TemplateCategory.startup:
        if (set != null) {
          await _service.generateSetStartup(
            outputPath: outPath,
            set: set.id,
            durationSecs: 4.0,
            onProgress: onProgress,
          );
          return;
        }
        final design = int.parse(
            spec.fileName.replaceAll('.mp4', '').replaceAll(RegExp(r'[^0-9]'), ''));
        await _service.generateFootballStartup(
          outputPath: outPath,
          design: design,
          durationSecs: 4.0,
        );
        return;
      case TemplateCategory.transition:
        final variant = spec.fileName
            .replaceAll('transition_', '')
            .replaceAll('.mp4', '');
        await _service.generateTransitionTemplate(
          outputPath: outPath,
          variant: variant,
          style: _transitionStyles[variant] ?? 'green',
          onProgress: onProgress,
        );
        return;
      case TemplateCategory.ending:
        final name = spec.fileName.replaceAll('.mp4', '');
        final bgm = _resolveEndingBgm();
        if (set != null) {
          await _service.generateSetEnding(
            outputPath: outPath,
            set: set.id,
            bgmPath: bgm,
            onProgress: onProgress,
          );
          return;
        }
        if (name.contains('dark')) {
          await _service.generateEndingTemplate(
            outputPath: outPath,
            bgmPath: bgm,
            style: 'dark',
          );
          return;
        }
        if (name.contains('green')) {
          await _service.generateEndingTemplate(
            outputPath: outPath,
            bgmPath: bgm,
            style: 'green',
          );
          return;
        }
        final design = int.parse(name.replaceAll(RegExp(r'[^0-9]'), ''));
        await _service.generateFootballEnding(
          outputPath: outPath,
          bgmPath: bgm,
          design: design,
          durationSecs: 3.0,
        );
        return;
    }
  }
}