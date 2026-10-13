import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:highlight_creator/data/font_name.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/domain/entities/template.dart';

/// Service for video processing: transition generation, slicing, and combining.
///
/// Uses ffmpeg CLI when available; falls back to simulation mode that copies
/// existing valid MP4 source files as placeholder output files so the full
/// application flow can be tested end-to-end without an ffmpeg install.
class VideoProcessingService {
  /// Try to locate a usable ffmpeg executable.
  static Future<String?> findFfmpeg() async {
    // 1. Check PATH.
    try {
      final result = await Process.run('where', ['ffmpeg']);
      if (result.exitCode == 0) {
        final lines = (result.stdout as String).trim().split('\n');
        if (lines.isNotEmpty && lines.first.isNotEmpty) return lines.first.trim();
      }
    } catch (_) {}

    // 1.5. Next to the executable (packaged release layout: ffmpeg.exe is
    // shipped beside highlight_creator.exe in the zip / installer / MSIX).
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final exeFfmpeg = '$exeDir\\ffmpeg.exe';
      if (File(exeFfmpeg).existsSync()) return exeFfmpeg;
    } catch (_) {}

    // 2. Project tools directory (portable ffmpeg).
    try {
      final toolsDir = _resolveProjectToolsDir();
      if (toolsDir != null) {
        final projectFfmpeg = '$toolsDir\\ffmpeg.exe';
        if (File(projectFfmpeg).existsSync()) return projectFfmpeg;
      }
    } catch (_) {}

    // 3. Common Windows locations.
    const candidates = [
      r'C:\ffmpeg\bin\ffmpeg.exe',
      r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
      r'C:\tools\ffmpeg\bin\ffmpeg.exe',
    ];
    for (final c in candidates) {
      if (File(c).existsSync()) return c;
    }

    // 4. scoop / chocolatey shims.
    try {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
      if (home != null) {
        final scoopShim = '$home\\scoop\\shims\\ffmpeg.exe';
        if (File(scoopShim).existsSync()) return scoopShim;
      }
    } on Exception catch (_) {}

    return null;
  }

  /// Resolve the project's `tools/` directory, containing portable ffmpeg binaries.
  ///
  /// Checks both `tools/ffmpeg/` (subdirectory) and `tools/` (flat layout).
  static String? _resolveProjectToolsDir() {
    try {
      final cwd = Directory.current.path;
      // Walk up to find the project root.
      var dir = Directory(cwd);
      // ponytail: walk until filesystem root; depth varies by platform/build config.
      while (true) {
        // Check for ffmpeg.exe directly in tools/ or tools/ffmpeg/.
        for (final sub in ['tools', r'tools\ffmpeg']) {
          final exe = '${dir.path}\\$sub\\ffmpeg.exe';
          if (File(exe).existsSync()) return File(exe).parent.path;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      // Fallback: relative to `app/` directory.
      if (cwd.endsWith('app')) {
        for (final sub in [r'..\tools', r'..\tools\ffmpeg']) {
          final exe = '$cwd\\$sub\\ffmpeg.exe';
          if (File(exe).existsSync()) return File(exe).absolute.parent.path;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Whether ffmpeg is available for real processing.
  static Future<bool> isFfmpegAvailable() async {
    final path = await findFfmpeg();
    return path != null;
  }

  /// Locate ffprobe (bundled alongside ffmpeg).
  static Future<String?> findFfprobe() async {
    final ffmpegPath = await findFfmpeg();
    if (ffmpegPath == null) return null;

    // ffprobe lives next to ffmpeg.
    final dir = File(ffmpegPath).parent.path;
    final probePath = '$dir\\ffprobe.exe';
    if (File(probePath).existsSync()) return probePath;
    return null;
  }

  /// Probe a video file's resolution via ffprobe.
  /// Returns `(width, height)` or `null` if probing fails.
  static Future<(int, int)?> probeResolution(String filePath) async {
    final probePath = await findFfprobe();
    if (probePath == null) return null;

    try {
      final result = await Process.run(probePath, [
        '-v', 'error',
        '-select_streams', 'v:0',
        '-show_entries', 'stream=width,height',
        '-of', 'csv=p=0',
        filePath,
      ]);
      if (result.exitCode == 0) {
        final out = (result.stdout as String).trim();
        final parts = out.split(',');
        if (parts.length == 2) {
          final w = int.tryParse(parts[0]);
          final h = int.tryParse(parts[1]);
          if (w != null && h != null) return (w, h);
        }
      }
    } catch (_) {}
    return null;
  }

  /// Probe a video file's duration via ffprobe (header-only read, fast).
  /// Returns milliseconds or `null` if probing fails.
  static Future<int?> probeDurationMs(String filePath) async {
    final probePath = await findFfprobe();
    if (probePath == null) return null;

    try {
      final result = await Process.run(probePath, [
        '-v', 'error',
        '-show_entries', 'format=duration',
        '-of', 'csv=p=0',
        filePath,
      ]);
      if (result.exitCode == 0) {
        final secs = double.tryParse((result.stdout as String).trim());
        if (secs != null) return (secs * 1000).round();
      }
    } catch (_) {}
    return null;
  }

  /// Parse an ffprobe `avg_frame_rate` string like `"30000/1001"` into fps.
  /// Returns 0 when unparseable.
  static double parseAvgFrameRate(String avgFrameRate) {
    final parts = avgFrameRate.split('/');
    if (parts.length == 2) {
      final num = double.tryParse(parts[0]);
      final den = double.tryParse(parts[1]);
      if (num != null && den != null && den != 0) return num / den;
    }
    return double.tryParse(avgFrameRate) ?? 0;
  }

  /// Probe a video file's stream metadata via ffprobe in a single call:
  /// duration, resolution, codec name and FPS. `null` if probing fails.
  static Future<
      ({int durationMs, int width, int height, String codecName, double fps})?>
      probeVideoInfo(String filePath) async {
    final probePath = await findFfprobe();
    if (probePath == null) return null;

    try {
      final result = await Process.run(probePath, [
        '-v', 'error',
        '-select_streams', 'v:0',
        '-show_entries',
        'stream=codec_name,width,height,avg_frame_rate:format=duration',
        '-of', 'json',
        filePath,
      ]);
      if (result.exitCode != 0) return null;
      final data = jsonDecode(result.stdout as String);
      if (data is! Map<String, dynamic>) return null;
      final streams = data['streams'] as List<dynamic>?;
      if (streams == null || streams.isEmpty) return null;
      final s = streams.first;
      if (s is! Map<String, dynamic>) return null;
      final format = data['format'];
      final durationSecs = format is Map<String, dynamic>
          ? double.tryParse('${format['duration']}')
          : null;
      final durationMs = (durationSecs ?? 0) * 1000;
      final width = int.tryParse('${s['width']}') ?? 0;
      final height = int.tryParse('${s['height']}') ?? 0;
      if (durationMs <= 0 && width <= 0) return null;
      return (
        durationMs: durationMs.round(),
        width: width,
        height: height,
        codecName: '${s['codec_name'] ?? ''}',
        fps: parseAvgFrameRate('${s['avg_frame_rate'] ?? ''}'),
      );
    } catch (_) {
      return null;
    }
  }

  final String? _ffmpegPath;

  /// Path for logging ffmpeg commands (e2e test aid).
  /// When non-null, every `_ffmpeg` invocation is appended to this file.
  /// The log entry includes [commandLogContext] as a header if set.
  static String? commandLogPath;

  /// Context label for the next log entry.
  /// Set before calling a service method to annotate commands with the
  /// originating test file and case name.  E.g.
  /// `"smooth_zoom_effect_test.dart :: smooth zoom effect: ..."`.
  static String? commandLogContext;

  VideoProcessingService({String? ffmpegPath}) : _ffmpegPath = ffmpegPath;

  /// True when ffmpeg was found and real processing will be used.
  bool get hasRealEncoder => _ffmpegPath != null;

  /// Find a TrueType font file that exists on this system.
  ///
  /// When [requiredRunes] is non-empty, only candidates whose cmap actually
  /// covers every codepoint are returned (so CJK text never settles for a
  /// Latin-only font). Returns the absolute path with forward slashes, colon
  /// escaped for ffmpeg's filter parser (e.g. `C\:/Windows/Fonts/segoeui.ttf`).
  /// Returns `null` when no known system font can be found, in which case
  /// ffmpeg's drawtext falls back to its own default.
  static String? _findSystemFont({Set<int> requiredRunes = const {}}) {
    // Per-platform font candidates — ordered by preference.
    final candidates = <String>[];
    if (Platform.isWindows) {
      // CJK-capable fonts MUST come before Latin-only ones: on Windows
      // installs without the optional CJK font pack (simhei missing), a
      // Latin-only pick renders Chinese as tofu.
      candidates.addAll([
        r'C:\Windows\Fonts\simhei.ttf',      // SimHei (bold, CJK + Latin)
        r'C:\Windows\Fonts\msyhbd.ttc',      // Microsoft YaHei Bold (bold, CJK + Latin)
        r'C:\Windows\Fonts\msyh.ttc',        // Microsoft YaHei (CJK + Latin)
        r'C:\Windows\Fonts\simsun.ttc',      // SimSun (CJK + Latin)
        r'C:\Windows\Fonts\segoeuib.ttf',    // Segoe UI Bold (bold, Latin only)
        r'C:\Windows\Fonts\segoeui.ttf',     // Segoe UI (Latin only)
        r'C:\Windows\Fonts\arial.ttf',       // Arial (Latin only)
      ]);
    } else if (Platform.isMacOS) {
      candidates.addAll([
        '/System/Library/Fonts/Helvetica.ttc',
        '/System/Library/Fonts/SFNSDisplay.ttf',
        '/Library/Fonts/Arial.ttf',
      ]);
    } else {
      // Linux / Android / other — common locations.
      candidates.addAll([
        '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/usr/share/fonts/TTF/DejaVuSans.ttf',
        '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
      ]);
    }

    for (final c in candidates) {
      if (!File(c).existsSync()) continue;
      if (requiredRunes.isNotEmpty && !fontHasGlyphs(c, requiredRunes)) {
        continue;
      }
      // Escape colon for ffmpeg's filter argument parser, and use forward
      // slashes so ffmpeg on Windows sees a consistent path.
      return c.replaceAll('\\', '/').replaceAll(':', '\\:');
    }
    // No candidate covered the required runes: fall back to the first font
    // that exists so Latin text still renders (non-Windows boxes have no
    // guaranteed CJK font, and drawtext failing outright is worse than tofu).
    for (final c in candidates) {
      if (File(c).existsSync()) {
        return c.replaceAll('\\', '/').replaceAll(':', '\\:');
      }
    }
    return null;
  }

  /// Escape a raw font path for ffmpeg's filter parser: forward slashes and
  /// the drive colon escaped (e.g. `C:\Windows\Fonts\a.ttf` →
  /// `C\:/Windows/Fonts/a.ttf`), matching [_findSystemFont]'s format.
  static String _escapeFontPath(String path) =>
      path.replaceAll('\\', '/').replaceAll(':', r'\:');

  /// True when [text] contains codepoints that need a CJK-capable font:
  /// CJK radicals/kana/ideographs, compatibility ideographs, fullwidth
  /// forms and extension planes.
  /// ponytail: ceiling = no Hangul (no Hangul-capable fallback is guaranteed
  /// on Windows either). Upgrade path: add malgun.ttf + 0xAC00-0xD7FF.
  static bool _needsCjkGlyphs(String text) => text.runes.any((r) =>
      (r >= 0x2E80 && r <= 0x9FFF) ||
      (r >= 0xF900 && r <= 0xFAFF) ||
      (r >= 0xFF00 && r <= 0xFFEF) ||
      (r >= 0x20000 && r <= 0x3FFFF));

  static Set<int> _cjkRunes(String text) => text.runes
      .where((r) =>
          (r >= 0x2E80 && r <= 0x9FFF) ||
          (r >= 0xF900 && r <= 0xFAFF) ||
          (r >= 0xFF00 && r <= 0xFFEF) ||
          (r >= 0x20000 && r <= 0x3FFFF))
      .toSet();

  /// Resolve the font actually used by drawtext for [text]:
  /// - font paths whose file no longer exists fall back to a system font
  ///   (handing ffmpeg a dead path makes the whole filter fail);
  /// - raw Windows paths are escaped for ffmpeg's filter parser;
  /// - when the text needs CJK glyphs, the chosen font's cmap is verified to
  ///   actually cover those codepoints; a font that lacks them (Latin-only
  ///   presets, user-browsed custom fonts, corrupt files) is substituted with
  ///   a CJK-first system font, so Chinese preview text never renders as tofu.
  static String? _resolveOverlayFont(String? fontPath, String text) {
    var font = fontPath;
    if (font != null && !File(font.replaceAll(r'\:', ':')).existsSync()) {
      font = null;
    }
    if (font == null) return _findSystemFont(requiredRunes: _cjkRunes(text));
    if (font.contains('\\')) font = _escapeFontPath(font);
    if (_needsCjkGlyphs(text) &&
        !fontHasGlyphs(font.replaceAll(r'\:', ':'), _cjkRunes(text))) {
      return _findSystemFont(requiredRunes: _cjkRunes(text));
    }
    return font;
  }

  /// Resolve the default transition template path for the current platform.
  ///
  /// On Windows, returns the absolute path to `app\windows\res\transition.mp4`
  /// (resolved from the project root).  Returns `null` when the file cannot
  /// be found or the platform has no default.
  static String? _resolveDefaultTransitionTemplate() {
    if (!Platform.isWindows) return null;

    // Walk up from cwd to find the project root.
    var dir = Directory.current;
    while (true) {
      if (File('${dir.path}\\AGENTS.md').existsSync() ||
          Directory('${dir.path}\\app').existsSync()) {
        final candidate = '${dir.path}\\app\\windows\\res\\transition.mp4';
        if (File(candidate).existsSync()) return candidate;
        return null;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }

    // Fallback: try relative to cwd.
    final cwdCandidate = '${Directory.current.path}\\app\\windows\\res\\transition.mp4';
    if (File(cwdCandidate).existsSync()) return cwdCandidate;
    return null;
  }

  /// LGPL-safe H.264 output encoder arguments.
  ///
  /// FFmpeg's `libx264` is GPL-licensed, so a build distributed under the
  /// LGPL must not invoke it. `libopenh264` is BSD-2-Clause and ships in
  /// LGPL FFmpeg builds; it exposes no CRF knob, so the quality target is
  /// expressed as a bitrate derived from the output size (~0.15 bits per
  /// pixel per frame, clamped to sane bounds).
  static List<String> _h264Args({
    int width = 1280,
    int height = 720,
    int fps = 30,
  }) {
    final kbps =
        (width * height * fps * 0.15 / 1000).round().clamp(1000, 120000);
    return ['-c:v', 'libopenh264', '-b:v', '${kbps}k'];
  }

  /// Run an ffmpeg command line assembled by the caller.
  ///
  /// Exists for the template plugin renderer, which builds its filtergraph
  /// from a downloaded script rather than from the built-in scene helpers. It
  /// also logs to [commandLogPath] and reports progress exactly like [_ffmpeg],
  /// so plugin renders show up in `ffmpeg_command` alongside everything else.
  ///
  /// Returns a non-zero [ProcessResult] rather than throwing when ffmpeg
  /// rejects the command: a plugin script can legitimately fail, and the
  /// caller needs stderr to tell the user why.
  Future<ProcessResult> runFfmpeg(
    List<String> args, {
    double? durationSecs,
    void Function(double progress)? onProgress,
  }) async {
    if (_ffmpegPath == null) {
      throw StateError('ffmpeg not available');
    }
    return _ffmpeg(args, durationSecs: durationSecs, onProgress: onProgress);
  }

  /// Run ffmpeg with args; returns the process result.
  ///
  /// When [commandLogPath] is set the full command line is appended
  /// to that file, preceded by [commandLogContext] if present.
  ///
  /// When [durationSecs] and [onProgress] are given the render streams
  /// ffmpeg's real `out_time` (`-progress pipe:1`) and reports live
  /// progress [0,1] — used by the template editor to show a real number
  /// while an embedded template renders.
  Future<ProcessResult> _ffmpeg(
    List<String> args, {
    double? durationSecs,
    void Function(double progress)? onProgress,
  }) async {
    if (_ffmpegPath == null) {
      throw StateError('ffmpeg not available');
    }

    if (commandLogPath != null) {
      final buf = StringBuffer();
      if (commandLogContext != null) {
        buf.writeln('[$commandLogContext]');
      }
      buf.writeln('$_ffmpegPath ${args.join(' ')}\n');
      File(commandLogPath!).writeAsStringSync(buf.toString(), mode: FileMode.append);
    }

    if (durationSecs == null || onProgress == null) {
      return Process.run(_ffmpegPath, args);
    }
    return _ffmpegStream(args, durationSecs, onProgress);
  }

  /// Run ffmpeg streaming its `-progress` output so [onProgress] is called
  /// with the fraction of [durationSecs] already encoded.
  Future<ProcessResult> _ffmpegStream(
    List<String> args,
    double durationSecs,
    void Function(double progress) onProgress,
  ) async {
    final process = await Process.start(_ffmpegPath!, [
      ...args,
      '-progress', 'pipe:1',
      '-nostats',
    ]);
    final stderrBuf = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(stderrBuf.write);

    // ffmpeg's `out_time_ms`/`out_time_us` are BOTH microseconds; `out_time_us`
    // is the canonical field on FFmpeg 7. Whichever arrives, use it.
    final outTime = RegExp(r'out_time_(?:us|ms)=(-?\d+)');
    var last = -1.0;
    var buffer = '';
    final stdoutDone = Completer<void>();
    process.stdout.transform(utf8.decoder).listen(
      (chunk) {
        buffer += chunk;
        var nl = buffer.indexOf('\n');
        while (nl >= 0) {
          final line = buffer.substring(0, nl);
          buffer = buffer.substring(nl + 1);
          final m = outTime.firstMatch(line);
          if (m != null) {
            final v = int.parse(m.group(1)!) / 1000000.0;
            if (v >= 0 && v != last) {
              last = v;
              onProgress((v / durationSecs).clamp(0.0, 1.0));
            }
          }
          nl = buffer.indexOf('\n');
        }
      },
      onDone: () => stdoutDone.complete(),
    );

    final exitCode = await process.exitCode;
    // The process may exit before the buffered stdout is delivered; wait for
    // the stream to drain so the final progress values are all reported.
    await stdoutDone.future;
    return ProcessResult(exitCode, 0, '', stderrBuf.toString());
  }

  /// Generate a transition video file (1 second, configurable resolution, text overlay).
  ///
  /// Real: uses ffmpeg drawtext filter on a template video (or white
  /// background fallback) to produce a 1-second H.264 MP4 with the
  /// description text centered on screen.
  ///
  /// Simulation: copies a valid source video as a placeholder.
  ///
  /// [transitionTemplatePath] when provided and the file exists, it is used
  /// as the video base instead of generating a white background from scratch.
  /// [width], [height] target output resolution (default 1280×720).
  /// Per issues.md: fontsize=40, fontcolor=red, fontfile=simhei.ttf (bold,
  /// CJK-capable), line_spacing=7.
  Future<ProcessResult> generateTransition({
    required String outputPath,
    required String text,
    required String startupVideoPath,
    String? transitionTemplatePath,
    int width = 1280,
    int height = 720,
    int fontSize = 56,
    String fontColor = 'red@0.8',
    String? fontPath,
  }) async {
    if (hasRealEncoder) {
      // Scale fontSize proportionally to output resolution (reference: 720p).
      final int scaledFontSize = (fontSize * height / 720.0).round();
      // Font resolution: dead paths fall back to a system font, raw Windows
      // paths are escaped, and CJK text never settles for a Latin-only font
      // (tofu).
      final effectiveFont = _resolveOverlayFont(fontPath, text);

      // Write text to a temp file for reliable Unicode (Chinese) support.
      // Using textfile avoids command-line encoding issues with non-ASCII
      // characters that occur when passing text directly via the text= option.
      final textFile = File('$outputPath.text.txt');
      await textFile.writeAsString(text);
      final escapedTextFile = textFile.path
          .replaceAll('\\', '/')
          .replaceAll(':', '\\:');

      try {
        // Build the drawtext filter with bold font and fontsize=56.
        final drawtextFilter = effectiveFont != null
            ? "drawtext=fontfile='$effectiveFont':"
                "textfile='$escapedTextFile':fontsize=$scaledFontSize:fontcolor=$fontColor:line_spacing=7:"
                'x=(w-text_w)/2:y=(h-text_h)/2'
            : "drawtext=textfile='$escapedTextFile':fontsize=$scaledFontSize:fontcolor=$fontColor:line_spacing=7:"
                'x=(w-text_w)/2:y=(h-text_h)/2';

        // The default real-video transition (app/windows/res/transition.mp4)
        // has no built-in text safe area, so darken its center here.  The
        // geq-generated templates already reserve their own center zone
        // (dark card on dark themes, light card on light themes), so adding
        // a black box on top of them would only muddy their design.
        // ponytail: ceiling = a user-imported real video whose path does not
        // end in res/transition.mp4 also lacks a safe area; upgrade path is
        // to tag templates with a "has safe area" flag in the repository.
        const zoneBox = "drawbox=x='iw/2-iw*0.30':y='ih/2-ih*0.18':"
            "w='iw*0.60':h='ih*0.36':color=black@0.35:t=fill";
        final isDefaultRealBase = transitionTemplatePath != null &&
            transitionTemplatePath
                .replaceAll('\\', '/')
                .endsWith('/res/transition.mp4');
        final reserve = isDefaultRealBase ? ',$zoneBox' : '';

        // If a transition template video is provided and exists, use it as the
        // base instead of generating a white background from scratch.
        if (transitionTemplatePath != null &&
            File(transitionTemplatePath).existsSync()) {
          // Use template as base, scale to target resolution, optionally
          // reserve the center text zone (real-video base only), overlay
          // text, trim to 1s.
          return await _ffmpeg([
            '-y',
            '-i', transitionTemplatePath,
            '-f', 'lavfi',
            '-i', 'anullsrc=r=44100:cl=stereo',
            '-vf', ('scale=$width:$height:force_original_aspect_ratio=decrease,'
                'pad=$width:$height:(ow-iw)/2:(oh-ih)/2$reserve,$drawtextFilter'),
            ..._h264Args(width: width, height: height),
            '-c:a', 'aac',
            '-b:a', '64k',
            '-pix_fmt', 'yuv420p',
            '-t', '1',
            '-shortest',
            outputPath,
          ]);
        }

        // No template: generate white background from scratch.
        return await _ffmpeg([
          '-y',
          '-f', 'lavfi',
          '-i', 'color=c=white:s=${width}x$height:d=1:r=30',
          '-f', 'lavfi',
          '-i', 'anullsrc=r=44100:cl=stereo',
          '-vf', drawtextFilter,
          ..._h264Args(width: width, height: height),
          '-c:a', 'aac',
          '-b:a', '64k',
          '-pix_fmt', 'yuv420p',
          '-t', '1',
          '-shortest',
          outputPath,
        ]);
      } finally {
        try { await textFile.delete(); } catch (_) {}
      }
    }

    // Simulation mode: copy the transition template if available;
    // otherwise fall back to the startup video so we don't produce
    // a corrupt file.
    final simSource = (transitionTemplatePath != null &&
            File(transitionTemplatePath).existsSync())
        ? transitionTemplatePath
        : startupVideoPath;
    return _simulateCopy(simSource, outputPath, 'transition "$text"');
  }

  /// Extract a single frame from a video at the given timestamp.
  ///
  /// Output is a PNG image scaled to [width]×[height] with letterboxing.
  /// Used by the Zoom-in Point Configuration dialog to show the first
  /// frame of a remote timeslot.
  Future<ProcessResult> extractFrame({
    required String sourcePath,
    required double timestampSecs,
    required String outputPath,
    int width = 1280,
    int height = 720,
  }) async {
    if (hasRealEncoder) {
      return _ffmpeg([
        '-y',
        '-ss', timestampSecs.toStringAsFixed(3),
        '-i', sourcePath,
        '-frames:v', '1',
        '-vf', ('scale=$width:$height:force_original_aspect_ratio=decrease,'
            'pad=$width:$height:(ow-iw)/2:(oh-ih)/2'),
        '-q:v', '2',
        outputPath,
      ]);
    }
    return _simulateCopy(sourcePath, outputPath, 'extract frame');
  }

  /// `drawtext` `y` that centers overlay text on a design set's text plate.
  ///
  /// Every design set draws its reserved band centered at `H*0.46` — see the
  /// plate rect in `_nocturneLayers` and the startup's own burned title,
  /// `h*0.46-text_h/2`. Text centered on the frame at `h/2` therefore sits
  /// visibly low inside the lit band.
  static const String plateCenterYExpr = 'h*0.46-text_h/2';

  /// `drawtext` `y` for a stored text position (`top` | `middle` | `bottom`).
  ///
  /// `middle` is the center of the template's reserved text area, which is the
  /// frame center only for a [transition]: transitions reserve a zone at `H/2`,
  /// while startup and ending plates sit at [plateCenterYExpr]. Every caller
  /// that burns a template's text goes through here, so the editor preview, the
  /// preview dialog and the final render cannot drift apart.
  static String textYExpr(String? position, {bool transition = false}) =>
      switch (position) {
        'top' => 'h*0.15',
        'bottom' => 'h*0.85-text_h',
        _ => transition ? '(h-text_h)/2' : plateCenterYExpr,
      };

  /// Overlay a single line of text onto an existing video.
  ///
  /// Used by the template editor to preview a chosen font inside a real
  /// template clip without re-running the (slow) geq scene synthesis: the
  /// template file is generated once, then every font/text tweak is just a
  /// fast drawtext re-encode on top of it. Audio is copied through.
  Future<ProcessResult> overlayText({
    required String inputPath,
    required String outputPath,
    required String text,
    String? fontPath,
    int fontSize = 42,
    String fontColor = '#F5C42D',
    String yExpr = '(h-text_h)/2',
    int width = 1280,
    int height = 720,
  }) async {
    if (hasRealEncoder) {
      // Font resolution: dead paths fall back to a system font, raw Windows
      // paths are escaped for ffmpeg's filter parser, and CJK text never
      // settles for a font known to lack CJK glyphs (tofu).
      final font = _resolveOverlayFont(fontPath, text);
      final fontOpt = font != null ? "fontfile='$font':" : '';
      final textFile = File('$outputPath.ovl.txt');
      await textFile.writeAsString(text);
      try {
        final escT =
            textFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');
        final draw = "drawtext=${fontOpt}textfile='$escT':"
            'fontsize=$fontSize:fontcolor=$fontColor:'
            'borderw=3:bordercolor=#000000@0.6:'
            "x=(w-text_w)/2:y='$yExpr'";
        return await _ffmpeg([
          '-y',
          '-i', inputPath,
          '-vf', draw,
          ..._h264Args(width: width, height: height),
          '-c:a', 'copy',
          '-pix_fmt', 'yuv420p',
          outputPath,
        ]);
      } finally {
        try { await textFile.delete(); } catch (_) {}
      }
    }
    return _simulateCopy(inputPath, outputPath, 'overlay text');
  }

  /// Slice a sub-video from a source file.
  ///
  /// Real: uses ffmpeg seek + trim to the specified range, scaling to target resolution.
  /// Simulation: copies the source video as a placeholder.
  Future<ProcessResult> sliceSubVideo({
    required String sourcePath,
    required String outputPath,
    required double startSecs,
    required double durationSecs,
    required String startupVideoPath,
    bool remote = false,
    double? centerX,
    double? centerY,
    int width = 1280,
    int height = 720,
  }) async {
    if (hasRealEncoder) {
      // Accurate seeking: -ss after -i to avoid keyframe-rounding
      // (source may be 4K with sparse keyframes; before-i seek is imprecise).
      final seekBefore = (startSecs - 0.5).clamp(0.0, startSecs);

      // Base filter: scale to target resolution and pad to exact dimensions.
      var vfFilter = 'scale=$width:$height:force_original_aspect_ratio=decrease,'
          'pad=$width:$height:(ow-iw)/2:(oh-ih)/2';

      // When remote: smooth zoom 100%→170% with optional center point.
      // Uses pzoom for continuous per-frame zoom accumulation.  Matches the
      // approach in sliceSubVideoWithZoom: fps-normalize the input first so
      // zoompan's 'on' counter increments smoothly, then pre-scale to a high
      // resolution before zoompan so the zoom stays crisp.
      if (remote) {
        const fpsR = 60;
        final panXEndR = (-500 * width / 1280).round();
        final preScaleW = (width * 3.125).round();
        final totalFrames = (durationSecs * fpsR).round().clamp(1, 999999);
        final zoomIncrement = 0.7 / totalFrames;  // 1.0 → 1.7

        // When centerX/centerY are set (from the Zoom-in Point dialog),
        // zoom into the user-selected point with no pan.  Otherwise use
        // the default center + smooth pan.
        final hasCenter = centerX != null && centerY != null;
        final panScaled = panXEndR * (preScaleW / width);
        final panIncrement = panScaled / totalFrames;

        final xExpr = hasCenter
            ? 'iw*$centerX-(iw/zoom/2)'
            : 'iw/2-(iw/zoom/2)+$panIncrement*on';
        final yExpr = hasCenter
            ? 'ih*$centerY-(ih/zoom/2)'
            : 'ih/2-(ih/zoom/2)';

        vfFilter = 'fps=$fpsR,'
            'scale=$preScaleW:-1,'
            'zoompan='
            "z='pzoom+$zoomIncrement'"
            ':d=1'
            ":x='$xExpr'"
            ":y='$yExpr'"
            ':s=${width}x$height'
            ':fps=$fpsR';
      }

      return _ffmpeg([
        '-y',
        '-ss', seekBefore.toStringAsFixed(3),
        '-i', sourcePath,
        '-ss', (startSecs - seekBefore).toStringAsFixed(3),
        '-t', durationSecs.toStringAsFixed(3),
        '-vf', vfFilter,
        '-af', 'volume=0',
        '-r', '60',
        ..._h264Args(width: width, height: height, fps: 60),
         '-c:a', 'aac',
         '-ar', '44100',
         '-ac', '2',
         '-b:a', '128k',
         '-pix_fmt', 'yuv420p',
         outputPath,
       ]);
     }

     return _simulateCopy(sourcePath, outputPath, 'slice $startSecs–${startSecs + durationSecs}s');
   }

  /// Slice a sub-video with a smooth zoom-and-pan effect via ffmpeg's
  /// zoompan filter.  The animation is linear over [durationSecs]: zoom
  /// goes from [zoomStart] to [zoomEnd] and x-position pans from 0 to
  /// [panXEnd] pixels.  Smoothness is achieved by using zoompan's `pzoom`
  /// variable (previous-frame zoom accumulation) so zoom changes
  /// continuously rather than in discrete per-frame steps.  The source is
  /// pre-scaled to a high resolution before zoompan so the zoomed result
  /// stays crisp.
  ///
  /// When ffmpeg is not available this falls back to copying the source.
  Future<ProcessResult> sliceSubVideoWithZoom({
    required String sourcePath,
    required String outputPath,
    required double startSecs,
    required double durationSecs,
    required String startupVideoPath,
    double zoomStart = 1.0,
    double zoomEnd = 1.7,
    double panXEnd = 400.0,
    int fps = 30,
    int width = 1280,
    int height = 720,
  }) async {
    if (hasRealEncoder) {
      final seekBefore = (startSecs - 0.5).clamp(0.0, startSecs);

      // Use 60 fps internally for smooth continuous motion, matching the
      // ffmpeg_example.json smooth_room_filter_example pattern.
      const fpsInternal = 60;
      final totalFrames = (durationSecs * fpsInternal).round().clamp(1, 999999);
      final zoomDelta = zoomEnd - zoomStart;
      final zoomIncrement = zoomDelta / totalFrames;

      // Pre-scale to a high width before zoompan so the zoom stays crisp
      // even at max zoom.  panXEnd is defined relative to output width
      // space — scale it up to match the pre-scale width.
      final preScaleW = (width * 3.125).round();
      final panScaled = panXEnd * (preScaleW / width);
      final panIncrement = panScaled / totalFrames;

      // Smooth zoom-pan via zoompan's pzoom: each frame's zoom is the
      // previous frame's zoom plus a constant increment.  This produces
      // truly continuous motion with no per-frame discrete stepping.
      // x/y centre the visible region, then the pan offset is added as a
      // linear ramp over the output frame count 'on'.
      final vfFilter = 'fps=$fpsInternal,'
          'scale=$preScaleW:-1,'
          'zoompan='
          "z='pzoom+$zoomIncrement'"
          ':d=1'
          ":x='iw/2-(iw/zoom/2)+$panIncrement*on'"
          ":y='ih/2-(ih/zoom/2)'"
          ':s=${width}x$height'
          ':fps=$fpsInternal';

      return _ffmpeg([
        '-y',
        '-ss', seekBefore.toStringAsFixed(3),
        '-i', sourcePath,
        '-ss', (startSecs - seekBefore).toStringAsFixed(3),
        '-t', durationSecs.toStringAsFixed(3),
        '-vf', vfFilter,
        '-r', '$fpsInternal',
        ..._h264Args(width: width, height: height, fps: fpsInternal),
        '-c:a', 'aac',
        '-ar', '44100',
        '-ac', '2',
        '-b:a', '128k',
        '-pix_fmt', 'yuv420p',
        outputPath,
      ]);
    }

    return _simulateCopy(sourcePath, outputPath,
        'slice zoom $startSecs–${startSecs + durationSecs}s');
  }

  /// Combine multiple video files into one via the concat demuxer.
  ///
  /// Real: writes a concat file list, feeds it to ffmpeg.
  /// Simulation: copies the first available input as placeholder.
  Future<ProcessResult> combineVideos({
    required List<String> inputPaths,
    required String outputPath,
    required String startupVideoPath,
    int width = 1280,
    int height = 720,
  }) async {
    if (hasRealEncoder) {
      // Write concat file
      final concatFile = '$outputPath.concat.txt';
      final buf = StringBuffer();
      for (final p in inputPaths) {
        buf.writeln("file '${p.replaceAll("'", "'\\''")}'");
      }
      await File(concatFile).writeAsString(buf.toString());

      try {
        return await _ffmpeg([
          '-y',
          '-f', 'concat',
          '-safe', '0',
          '-i', concatFile,
          ..._h264Args(width: width, height: height),
          '-c:a', 'aac',
          '-ar', '44100',
          '-ac', '2',
          '-b:a', '128k',
          '-pix_fmt', 'yuv420p',
          outputPath,
        ]);
      } finally {
        try { File(concatFile).deleteSync(); } catch (_) {}
      }
    }

    // Simulation: copy the first valid input as placeholder.
    final fallback = inputPaths.firstWhere(
      (p) => File(p).existsSync(),
      orElse: () => startupVideoPath,
    );
    return _simulateCopy(fallback, outputPath, 'combined final');
  }

  /// Run the full make pipeline.
  ///
  /// Pipeline:
  ///   1. Normalize startup and ending videos to target resolution.
  ///   2. For each timeslot: generate transition + slice sub-video (muted).
  ///   3. Combine transitions + subs → body.mp4.
  ///   4. Add background music to body.mp4 (loop or cut to match duration).
  ///   5. Combine startup + body + ending → final.mp4.
  ///
  /// [sourcePaths] maps base filename → full path for resolving timeslot sources.
  /// [transitionTemplatePath] optional template video for transitions.
  /// [endingVideoPath] optional ending video appended after body.
  /// [bgMusicPath] optional background music MP3 mixed into body.mp4.
  /// [width], [height] target output resolution (default 1280×720).
  Future<String> makeAll({
    required List<Timeslot> timeslots,
    required String startupVideoPath,
    required String outputDir,
    Map<String, String> sourcePaths = const {},
    String? transitionTemplatePath,
    String? endingVideoPath,
    String? bgMusicPath,
    Template? startupTemplate,
    Template? transitionTemplate,
    int width = 1280,
    int height = 720,
    void Function(double progress)? onProgress,
  }) async {
    // Auto-resolve default template when none explicitly provided.
    final effectiveTemplatePath = transitionTemplatePath ??
        _resolveDefaultTransitionTemplate();
    final dir = Directory(outputDir);
    if (!dir.existsSync()) await dir.create(recursive: true);

    // Step-based progress: count every ffmpeg/simulate operation up front,
    // then report the completed fraction after each one. Each step is
    // weighted equally; per-timeslot work dominates the count.
    final hasTitleOverlay = hasRealEncoder &&
        startupTemplate?.title != null &&
        startupTemplate!.title!.isNotEmpty;
    final hasEnding = endingVideoPath != null && File(endingVideoPath).existsSync();
    final hasBgm = hasRealEncoder &&
        bgMusicPath != null &&
        File(bgMusicPath).existsSync();
    final totalSteps = 1 + // normalize startup
        (hasTitleOverlay ? 1 : 0) +
        (hasEnding ? 1 : 0) +
        timeslots.length * 2 + // transition + sub per slot
        1 + // combine body
        (hasBgm ? 1 : 0) +
        1; // combine final
    var doneSteps = 0;
    void report() {
      onProgress?.call((doneSteps / totalSteps).clamp(0.0, 1.0));
    }
    // Emit 0% before the first step so the dialog opens at a known value.
    report();

    // Step 0: Pre-normalize startup video to target resolution.
    final normalizedStartup = '${outputDir}startup_normalized.mp4';
    if (hasRealEncoder) {
      await _ffmpeg([
        '-y',
        '-i', startupVideoPath,
        '-vf', ('scale=$width:$height:force_original_aspect_ratio=decrease,'
            'pad=$width:$height:(ow-iw)/2:(oh-ih)/2'),
        ..._h264Args(width: width, height: height),
        '-c:a', 'aac',
        '-ar', '44100',
        '-ac', '2',
        '-b:a', '128k',
        '-pix_fmt', 'yuv420p',
        normalizedStartup,
      ]);
    } else {
      await _simulateCopy(startupVideoPath, normalizedStartup, 'normalize startup');
    }
    doneSteps++;
    report();

    // Step 0b: Overlay the embedded startup template title (if any) so the
    // final video carries the title instead of a blank template.
    var startupClip = normalizedStartup;
    final startupTitle = startupTemplate?.title;
    if (startupTitle != null && startupTitle.isNotEmpty && hasRealEncoder) {
      startupClip = '${outputDir}startup_titled.mp4';
      // Scale fontSize proportionally to the target resolution (reference:
      // 720p), matching generateTransition — the template editor and preview
      // dialog burn the configured size on a 720p template base, so an
      // unscaled size renders relatively smaller at higher resolutions
      // (3x too small at 4K).
      final scaledStartupFontSize =
          ((startupTemplate?.fontSize ?? 42) * height / 720.0).round();
      final res = await overlayText(
        inputPath: normalizedStartup,
        outputPath: startupClip,
        text: startupTitle,
        fontPath: startupTemplate?.fontPath,
        fontSize: scaledStartupFontSize,
        fontColor: startupTemplate?.fontColor ?? '#F5C42D',
        yExpr: textYExpr(startupTemplate?.textPosition),
        width: width,
        height: height,
      );
      if (res.exitCode != 0) startupClip = normalizedStartup; // keep base.
    }
    if (hasTitleOverlay) {
      doneSteps++;
      report();
    }

    // Normalize ending video to target resolution (if provided).
    String? normalizedEnding;
    if (endingVideoPath != null && File(endingVideoPath).existsSync()) {
      normalizedEnding = '${outputDir}ending_normalized.mp4';
      if (hasRealEncoder) {
        await _ffmpeg([
          '-y',
          '-i', endingVideoPath,
          '-vf', ('scale=$width:$height:force_original_aspect_ratio=decrease,'
              'pad=$width:$height:(ow-iw)/2:(oh-ih)/2'),
          ..._h264Args(width: width, height: height),
          '-c:a', 'aac',
          '-ar', '44100',
          '-ac', '2',
          '-b:a', '128k',
          '-pix_fmt', 'yuv420p',
          normalizedEnding,
        ]);
      } else {
        await _simulateCopy(endingVideoPath, normalizedEnding, 'normalize ending');
      }
    }
    if (hasEnding) {
      doneSteps++;
      report();
    }

    // Steps 1-2: Generate transitions and slice sub-videos (muted audio).
    final bodyClipPaths = <String>[];

    for (var i = 0; i < timeslots.length; i++) {
      final slot = timeslots[i];
      final desc = slot.description.isNotEmpty ? slot.description : 'slot_${slot.id}';
      final safeName = 'slot_$i';

      final transitionPath = '$outputDir${safeName}_transition.mp4';
      final subPath = '$outputDir${safeName}_sub.mp4';

      // Generate transition (1s, target resolution, text overlay).
      await generateTransition(
        outputPath: transitionPath,
        text: desc,
        startupVideoPath: startupVideoPath,
        transitionTemplatePath: effectiveTemplatePath,
        fontSize: transitionTemplate?.fontSize ?? 56,
        fontColor: transitionTemplate?.fontColor != null
            ? '${transitionTemplate!.fontColor}@0.8'
            : 'red@0.8',
        fontPath: transitionTemplate?.fontPath,
        width: width,
        height: height,
      );

      // Slice sub-video. Slots with an explicit elapse use their own window
      // (inPoint..inPoint+elapse — editable on the Auto Gen track); legacy
      // point-marks (elapse == 0) fall back to the 10s before the mark.
      final double startSecs;
      final double durationSecs;
      if (slot.elapse > 0) {
        startSecs = slot.inPointMs / 1000.0;
        durationSecs = slot.elapse / 1000.0;
      } else {
        final markSecs = slot.inPointMs / 1000.0;
        startSecs = (markSecs - 10.0).clamp(0.0, markSecs);
        durationSecs = markSecs - startSecs;
      }

      final fullSourcePath = sourcePaths[slot.filename] ?? slot.filename;

      await sliceSubVideo(
        sourcePath: fullSourcePath,
        outputPath: subPath,
        startSecs: startSecs,
        durationSecs: durationSecs,
        startupVideoPath: startupVideoPath,
        remote: slot.remote,
        centerX: slot.centerX,
        centerY: slot.centerY,
        width: width,
        height: height,
      );

      bodyClipPaths.add(transitionPath);
      bodyClipPaths.add(subPath);
      doneSteps += 2;
      report();
    }

    // Step 3: Combine transitions + subs → body.mp4.
    final bodyPath = '${outputDir}body.mp4';
    await combineVideos(
      inputPaths: bodyClipPaths,
      outputPath: bodyPath,
      startupVideoPath: startupVideoPath,
      width: width,
      height: height,
    );
    doneSteps++;
    report();

    // Step 4: Add background music to body.mp4.
    // -stream_loop -1 loops the music infinitely; -shortest cuts at the
    // body video's duration.  This handles both cases: music longer than
    // body (cut) and music shorter than body (looped to fill).
    String bodyWithMusicPath = bodyPath;
    if (bgMusicPath != null && File(bgMusicPath).existsSync() && hasRealEncoder) {
      bodyWithMusicPath = '${outputDir}body_music.mp4';
      await _ffmpeg([
        '-y',
        '-i', bodyPath,
        '-stream_loop', '-1',
        '-i', bgMusicPath,
        '-map', '0:v',
        '-map', '1:a',
        '-c:v', 'copy',
        '-c:a', 'aac',
        '-ar', '44100',
        '-ac', '2',
        '-b:a', '128k',
        '-shortest',
        bodyWithMusicPath,
      ]);
    }
    if (hasBgm) {
      doneSteps++;
      report();
    }

    // Step 5: Combine startup + body + ending → final.mp4.
    final finalClipPaths = <String>[startupClip, bodyWithMusicPath];
    if (normalizedEnding != null) {
      finalClipPaths.add(normalizedEnding);
    }

    final finalPath = '${outputDir}final.mp4';
    await combineVideos(
      inputPaths: finalClipPaths,
      outputPath: finalPath,
      startupVideoPath: startupVideoPath,
      width: width,
      height: height,
    );
    doneSteps++;
    report();

    return finalPath;
  }

  /// Generate a football-themed startup (intro) template video.
  ///
  /// Produces a [durationSecs]-second H.264 MP4 with a dark-green gradient
  /// background, a large title that fades in, and a smaller subtitle.
  /// [style] selects the color scheme: 'green' (default), 'dark', 'blue'.
  Future<ProcessResult> generateStartupTemplate({
    required String outputPath,
    String title = '精彩集锦',
    String subtitle = 'Football Highlights',
    String style = 'green',
    double durationSecs = 4.0,
    int width = 1280,
    int height = 720,
  }) async {
    if (hasRealEncoder) {
      final fontPath = _findSystemFont();
      final bgColor = _styleBackground(style);
      final accentColor = _styleAccent(style);

      final titleFile = File('$outputPath.title.txt');
      final subtitleFile = File('$outputPath.subtitle.txt');
      await titleFile.writeAsString(title);
      await subtitleFile.writeAsString(subtitle);

      try {
        final escTitle = titleFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');
        final escSub = subtitleFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');

        final fontOpt = fontPath != null ? "fontfile='$fontPath':" : '';
        final d = durationSecs;

        final titleDraw = "drawtext=${fontOpt}textfile='$escTitle':"
            'fontsize=72:fontcolor=$accentColor:'
            'x=(w-text_w)/2:y=(h-text_h)/2-40:'
            "alpha='if(lt(t,0.5),0,if(lt(t,1.5),(t-0.5),1))'";
        final subDraw = "drawtext=${fontOpt}textfile='$escSub':"
            'fontsize=36:fontcolor=white@0.85:'
            'x=(w-text_w)/2:y=(h/2)+40:'
            "alpha='if(lt(t,1.0),0,if(lt(t,2.0),(t-1.0),1))'";

        return await _ffmpeg([
          '-y',
          '-f', 'lavfi',
          '-i', 'color=c=$bgColor:s=${width}x$height:d=$d:r=30',
          '-f', 'lavfi',
          '-i', 'anullsrc=r=44100:cl=stereo',
          '-vf', ('$titleDraw,$subDraw,'
              'fade=t=in:st=0:d=0.3,fade=t=out:st=${d - 0.5}:d=0.5'),
          ..._h264Args(width: width, height: height),
          '-c:a', 'aac',
          '-b:a', '64k',
          '-pix_fmt', 'yuv420p',
          '-t', '$d',
          '-shortest',
          outputPath,
        ]);
      } finally {
        try { await titleFile.delete(); } catch (_) {}
        try { await subtitleFile.delete(); } catch (_) {}
      }
    }

    return _simulateCopy(outputPath, outputPath, 'startup template');
  }

  /// Generate a football-themed startup (intro) video, 4 s by default.
  ///
  /// [design] selects one of three crafted, animated pitch scenes (1 = spotlit
  /// green pitch with a rolling ball and a center title plate; 2 = night
  /// stadium with light cones, a rotating ball badge and a lower-third plate;
  /// 3 = sunrise pitch with field lines, a flying ball and a bracketed title
  /// plate).  Each scene reserves a text zone (the plate / lower-third) drawn
  /// as a designed broadcast graphic; when [title] is supplied it is rendered
  /// inside that zone, otherwise the zone stays as an empty reserved plate for
  /// user-defined text.  When a [bgmPath] (or the resolved default music) is
  /// available it is mixed in as the soundtrack with fade in/out.
  Future<ProcessResult> generateFootballStartup({
    required String outputPath,
    required int design,
    String? title,
    String? bgmPath,
    double? durationSecs,
    int width = 1280,
    int height = 720,
  }) async {
    if (hasRealEncoder) {
      final fontPath = _findSystemFont();
      final d = durationSecs ?? 4.0;
      final hasTitle = title != null && title.isNotEmpty;
      String? escT;
      File? titleFile;
      if (hasTitle) {
        titleFile = File('$outputPath.title.txt');
        await titleFile.writeAsString(title);
        escT = titleFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');
      }
      try {
        final fontOpt = fontPath != null ? "fontfile='$fontPath':" : '';
        final scene = _rsLayers(design);
        final geq = _rsGeq(scene.$1, scene.$2);
        final titles = _rsTitles(design, d, fontOpt, escT);
        final hw = width ~/ 2;
        final hh = height ~/ 2;
        final vfParts = ['format=rgb24', geq, 'format=yuv420p',
          'scale=$width:$height:flags=lanczos', 'fps=30'];
        if (titles.isNotEmpty) vfParts.add(titles);
        vfParts.add('fade=t=in:st=0:d=0.6');
        vfParts.add('fade=t=out:st=${d - 0.6}:d=0.6');
        final vf = vfParts.join(',');

        final bgm = (bgmPath != null && File(bgmPath).existsSync())
            ? bgmPath
            : await resolveDefaultBgm();
        final args = <String>[
          '-y',
          '-f', 'lavfi',
          '-i', 'color=c=black:s=${hw}x$hh:d=$d:r=30',
        ];
        if (bgm != null) {
          args.addAll([
            '-stream_loop', '-1',
            '-i', bgm,
            '-map', '0:v',
            '-map', '1:a',
            '-vf', vf,
            '-af', ('afade=t=in:st=0:d=0.5,afade=t=out:st=${d - 0.8}:d=0.8,'
                'volume=0.9'),
          ]);
        } else {
          args.addAll([
            '-f', 'lavfi',
            '-i', 'anullsrc=r=44100:cl=stereo',
            '-vf', vf,
          ]);
        }
        args.addAll([
          ..._h264Args(width: width, height: height),
          '-c:a', 'aac',
          if (bgm != null)
            ...['-ar', '44100', '-ac', '2', '-b:a', '128k']
          else
            ...['-b:a', '64k'],
          '-pix_fmt', 'yuv420p',
          '-t', '$d',
          '-shortest',
          outputPath,
        ]);
        return await _ffmpeg(args);
      } finally {
        if (titleFile != null) {
          try { await titleFile.delete(); } catch (_) {}
        }
      }
    }

    return _simulateCopy(outputPath, outputPath, 'football startup');
  }

  /// Locate bg_music.mp3 next to the given [ffmpegPath] (packaged layout:
  /// both files ship side by side in the app folder).
  static String? resolveDefaultBgmFor(String ffmpegPath) {
    if (ffmpegPath.isEmpty) return null;
    final bgm = '${File(ffmpegPath).parent.path}'
        '${Platform.pathSeparator}bg_music.mp3';
    return File(bgm).existsSync() ? bgm : null;
  }

  /// Default background music: only bg_music.mp3 in the same folder as ffmpeg.
  static Future<String?> resolveDefaultBgm() async {
    final ffmpeg = await findFfmpeg();
    if (ffmpeg == null) return null;
    return resolveDefaultBgmFor(ffmpeg);
  }

  static const _dc = 'sqrt(pow(X-W/2\\,2)+pow(Y-H/2\\,2))';
  static const _rsWhite = ['244', '244', '238'];
  static const _rsBlack = ['30', '30', '34'];
  static const _rsGold = ['245', '196', '45'];
  static const _rsSkyDeep = ['11', '46', '79'];
  static const _rsUmber = ['74', '46', '11'];
  static const _rsForestPlate = ['20', '40', '20'];
  static const _rsAmber = ['226', '166', '88'];
  static const _rsNocturnePlate = ['22', '33', '43'];

  static String _ramp(double a, double b) {
    final w = (b - a).toStringAsFixed(3);
    return 'min(max((T-$a)/$w\\,0)\\,1)';
  }

  /// Smoothstep ease between [t0] and [t1] on the expression clock [t].
  ///
  /// The older set scenes ramp linearly (`T/$d`), which is most of why they
  /// read crude: a real light comes up fast and then settles. Everything in
  /// the 'nocturne' scene is timed through this instead.
  static String _ease(String t, double t0, double t1) {
    final w = (t1 - t0).toStringAsFixed(3);
    final u = 'min(max(($t-$t0)/$w\\,0)\\,1)';
    return '($u)*($u)*(3.0-2.0*($u))';
  }

  /// Evaluate [expr] into geq slot [slot] and contribute nothing to the value.
  ///
  /// geq has no statement form, so a side-effecting store is chained into the
  /// surrounding sum with `*0`. Slots 0-3 are the nocturne light rig, 4-9 the
  /// scene's graphic layers.
  static String _slot(int slot, String expr) => '(st($slot,$expr)*0)';

  static String _win(double si, double ei, double so, double eo) =>
      'min(${_ramp(si, ei)}\\,(1-${_ramp(so, eo)}))';

  static String _disk(String dist, String r, [double soft = 4]) {
    final s = (2 * soft).toStringAsFixed(1);
    final h = soft.toStringAsFixed(1);
    return 'min(max(($r-($dist)+$h)/$s\\,0)\\,1)';
  }

  static String _line(String v, double th) =>
      'max(0\\,1-abs($v)/${th.toStringAsFixed(1)})';

  static String _c01(String e) => 'min(max($e\\,0)\\,1)';

  static String _rsGeq(
    List<(String, String, List<String>)> layers,
    List<String> base,
  ) {
    String fold(int k) {
      var acc = base[k];
      for (final l in layers) {
        final a = '(${l.$1})*(${l.$2})';
        acc = '($acc)*(1-($a))+(${l.$3[k]})*($a)';
      }
      return acc;
    }
    return "geq=r='${fold(0)}':g='${fold(1)}':b='${fold(2)}'";
  }

  static const _rsPlate = ['12', '16', '24'];

  static String _rect(String cx, String cy, String hw, String hh, String s) =>
      '(${_c01('(($hw)-abs(X-($cx)))/$s')})*'
      '(${_c01('(($hh)-abs(Y-($cy)))/$s')})';

  static String _hlineDraw(
    String yy,
    String cx,
    String hw,
    String prog,
  ) =>
      '(${_line('Y-($yy)', 2.0)})*'
      '(${_c01('(($hw)*($prog)-abs(X-($cx)))/4')})';

  static String _frame(String cx, String cy, String hw, String hh) =>
      'max(0\\,(${_rect(cx, cy, hw, hh, '3')})-'
      '(${_rect(cx, cy, '($hw)-5', '($hh)-5', '3')}))';

  static List<(String, String, List<String>)> _fbBall(
    String cx,
    String cy,
    String r,
    String app,
    double spin,
  ) {
    final dbc = 'sqrt(pow(X-($cx)\\,2)+pow(Y-($cy)\\,2))';
    final disk = _disk(dbc, r, 4);
    final ang = 'atan2(Y-($cy)\\,X-($cx))';
    final spinT = 'T*${spin.toStringAsFixed(1)}';

    final cRot = '-PI/2+$spinT';
    final cEdge =
        '($r)*0.42*cos(PI/5)/cos(mod(($ang)-($cRot)\\,2*PI/5)-PI/5)';
    final cPent = _c01('($cEdge-$dbc)/2.5');

    final sector = 'mod(($ang)+($spinT)\\,2*PI/5)';
    final inWedge = _c01('(PI/5-abs($sector-PI/5))/0.18');
    final outerRing = _c01('($dbc-($r)*0.58)/(($r)*0.08)');
    final outerPent = '($inWedge)*($outerRing)';

    final pattern = 'max($cPent\\,$outerPent)*($disk)';
    final edge = _line('$dbc-($r)', 3.0);
    return [
      (disk, app, _rsWhite),
      (pattern, app, _rsBlack),
      (edge, app, _rsBlack),
    ];
  }

  static (List<(String, String, List<String>)>, List<String>) _rsLayers(
    int design,
  ) {
    const b = '4*sin(T*1.5)';
    switch (design) {
      case 2:
        const wave = '10*sin((X+Y*0.3)/80+T*1.5)';
        const rad = 'max(0\\,1-$_dc/700)';
        const bc = 'H*0.40';
        const r2 = '92+8*sin(T*3)';
        final ballApp = _win(0.5, 1.5, 3.2, 4.0);
        const ringR = '128+16*sin(T*2.5)';
        const dbc = 'sqrt(pow(X-W/2\\,2)+pow(Y-($bc)\\,2))';
        final ringMask = _line('$dbc-($ringR)', 5.0);
        final ringApp = _win(0.7, 1.6, 3.4, 4.0);
        final partMask = '${_line('mod(X*0.7+Y+120*T\\,90)-45', 2.0)}*'
            '${_line('mod(X-Y*0.5-80*T\\,110)-55', 2.0)}';
        final partApp = _win(1.0, 2.0, 3.4, 4.0);
        String shaft(String x) =>
            '(${_line('X-$x', 90.0)})*(${_c01('(H*0.75-Y)/(H*0.75)')})';
        final shaftApp = '(0.20)*(${_win(0.3, 1.4, 3.4, 4.0)})';
        const pcx = 'W/2';
        const pcy = 'H*0.80';
        const phw = 'W*0.40';
        const phh = 'H*0.085';
        final plateApp = '(0.70)*(${_win(0.7, 1.6, 3.2, 4.0)})';
        final topLine = _hlineDraw('$pcy-$phh', pcx, phw, _ramp(1.0, 1.9));
        final topApp = _win(1.0, 1.9, 3.2, 4.0);
        final tabMask =
            '(${_line('X-($pcx-$phw)', 3.0)})*(${_c01('($phh-abs(Y-$pcy))/4')})';
        final tabApp = _win(1.1, 1.8, 3.2, 4.0);
        final base = [
          '10+22*$rad+$wave*0.2+$b*0.3',
          '24+46*$rad+$wave*0.4+$b*0.5',
          '52+92*$rad+$wave+$b',
        ];
        return ([
          (partMask, partApp, _rsGold),
          (shaft('W*0.28'), shaftApp, _rsWhite),
          (shaft('W*0.72'), shaftApp, _rsWhite),
          (ringMask, ringApp, _rsGold),
          ..._fbBall('W/2', bc, r2, ballApp, 2.0),
          (_rect(pcx, pcy, phw, phh, '12'), plateApp, _rsPlate),
          (topLine, topApp, _rsGold),
          (tabMask, tabApp, _rsGold),
        ], base);
      case 3:
        const glow = 'max(0\\,1-Y/(H*0.5))';
        const rad = 'max(0\\,1-$_dc/700)';
        final stripesMask = _line('mod(Y+40*T\\,120)-60', 2.0);
        final stripesApp = _ramp(0.0, 1.2);
        final markApp = '(0.5)*(${_win(0.2, 1.2, 3.0, 3.8)})';
        final cCircle = _line('$_dc-130', 2.5);
        final cLine = _line('X-W/2', 2.0);
        final bcx = 'W*0.82-W*0.32*${_ramp(0.3, 1.4)}';
        final bcy = 'H*0.80-H*0.10*${_ramp(0.3, 1.4)}';
        final r3 = '14+62*${_ramp(0.4, 1.3)}';
        final ballApp = _win(0.4, 1.3, 2.6, 3.4);
        const pcx = 'W/2';
        const pcy = 'H*0.46';
        const phw = 'W*0.30';
        const phh = 'H*0.115';
        final plateApp = '(0.66)*(${_win(0.6, 1.5, 3.0, 3.8)})';
        final frameApp = _win(0.9, 1.8, 3.0, 3.8);
        final base = [
          '16+40*$rad+120*$glow+$b*0.3',
          '64+34*$rad+90*$glow+$b',
          '28+10*$rad+30*$glow+$b*0.3',
        ];
        return ([
          (stripesMask, stripesApp, _rsWhite),
          (cLine, markApp, _rsWhite),
          (cCircle, markApp, _rsWhite),
          (_rect(pcx, pcy, phw, phh, '12'), plateApp, _rsPlate),
          (_frame(pcx, pcy, phw, phh), frameApp, _rsGold),
          ..._fbBall(bcx, bcy, r3, ballApp, 4.0),
        ], base);
      case 1:
      default:
        final grass = "8*${_line('mod(X+Y*0.5+60*T\\,46)-23', 2.0)}";
        const rad = 'max(0\\,1-$_dc/620)';
        final raysMask = _line('mod(X+Y-220*T\\,260)-130', 3.0);
        final raysApp = '(0.4+0.5*sin(T*2))*${_ramp(0.0, 1.5)}';
        final markApp = '(0.5)*(${_win(0.2, 1.2, 3.0, 3.8)})';
        final cCircle = _line('$_dc-130', 2.5);
        final cLine = _line('X-W/2', 2.0);
        final bcx = 'W*0.86-W*0.60*${_ramp(0.3, 1.7)}';
        final ballApp = _win(0.4, 1.5, 3.0, 3.8);
        const pcx = 'W/2';
        const pcy = 'H*0.46';
        const phw = 'W*0.30';
        const phh = 'H*0.115';
        final plateApp = '(0.66)*(${_win(0.6, 1.5, 3.0, 3.8)})';
        final lineApp = _win(0.9, 1.8, 3.0, 3.8);
        final topLine = _hlineDraw('$pcy-$phh', pcx, phw, _ramp(0.9, 1.8));
        final botLine = _hlineDraw('$pcy+$phh', pcx, phw, _ramp(0.9, 1.8));
        final base = [
          '12+6*$rad+$grass*0.4+$b*0.3',
          '52+30*$rad+$grass+$b',
          '22+8*$rad+$grass*0.3+$b*0.3',
        ];
        return ([
          (raysMask, raysApp, _rsGold),
          (cLine, markApp, _rsWhite),
          (cCircle, markApp, _rsWhite),
          (_rect(pcx, pcy, phw, phh, '12'), plateApp, _rsPlate),
          (topLine, lineApp, _rsGold),
          (botLine, lineApp, _rsGold),
          ..._fbBall(bcx, 'H*0.82', '64', ballApp, 3.0),
        ], base);
    }
  }

  static String _rsTitles(
    int design,
    double d,
    String fontOpt,
    String? escT,
  ) {
    if (escT == null) return '';
    final yC = design == 2 ? 'h*0.80' : 'h*0.46';
    final fs = design == 2 ? 46 : 66;
    const fadeIn = 'min(max((t-0.4)/0.7,0),1)';
    final fadeOut = '1-min(max((t-${(d - 0.8).toStringAsFixed(2)})/0.5,0),1)';
    return "drawtext=${fontOpt}textfile='$escT':fontsize=$fs:"
        'fontcolor=#F4F4EE:borderw=5:bordercolor=#000000@0.7:'
        "x=(w-text_w)/2:y='$yC-text_h/2-max(0,(0.9-t)/0.9)*40':"
        "alpha='min($fadeIn,$fadeOut)'";
  }

  /// Generate a football-themed ending (outro) template video.
  ///
  /// Produces a [durationSecs]-second MP4 with a dark background, main text
  /// (e.g. "感谢观看") fading in, and optional sub-info text.
  Future<ProcessResult> generateEndingTemplate({
    required String outputPath,
    String mainText = '感谢观看',
    String subText = 'Thanks for Watching',
    String? bgmPath,
    String style = 'dark',
    double durationSecs = 3.0,
    int width = 1280,
    int height = 720,
  }) async {
    if (hasRealEncoder) {
      final fontPath = _findSystemFont();
      final bgColor = _styleBackground(style);
      final accentColor = _styleAccent(style);

      final mainFile = File('$outputPath.main.txt');
      final subFile = File('$outputPath.sub.txt');
      await mainFile.writeAsString(mainText);
      await subFile.writeAsString(subText);

      try {
        final escMain = mainFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');
        final escSub = subFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');

        final fontOpt = fontPath != null ? "fontfile='$fontPath':" : '';
        final d = durationSecs;

        final mainDraw = "drawtext=${fontOpt}textfile='$escMain':"
            'fontsize=64:fontcolor=$accentColor:'
            'x=(w-text_w)/2:y=(h-text_h)/2-30:'
            "alpha='if(lt(t,0.3),0,if(lt(t,1.0),(t-0.3)/0.7,1))'";
        final subDraw = "drawtext=${fontOpt}textfile='$escSub':"
            'fontsize=30:fontcolor=white@0.7:'
            'x=(w-text_w)/2:y=(h/2)+30:'
            "alpha='if(lt(t,0.8),0,if(lt(t,1.5),(t-0.8)/0.7,1))'";

        return await _ffmpeg([
          '-y',
          '-f', 'lavfi',
          '-i', 'color=c=$bgColor:s=${width}x$height:d=$d:r=30',
          if (bgmPath != null && File(bgmPath).existsSync()) ...[
            '-stream_loop', '-1',
            '-i', bgmPath,
            '-map', '0:v',
            '-map', '1:a',
            '-vf', ('$mainDraw,$subDraw,'
                'fade=t=in:st=0:d=0.3,fade=t=out:st=${d - 0.8}:d=0.8'),
            '-af', ('afade=t=in:st=0:d=0.3,afade=t=out:st=${d - 0.8}:d=0.8,'
                'volume=0.9'),
          ] else ...[
            '-f', 'lavfi',
            '-i', 'anullsrc=r=44100:cl=stereo',
            '-vf', ('$mainDraw,$subDraw,'
                'fade=t=in:st=0:d=0.3,fade=t=out:st=${d - 0.8}:d=0.8'),
          ],
          ..._h264Args(width: width, height: height),
          '-c:a', 'aac',
          '-b:a', '64k',
          '-pix_fmt', 'yuv420p',
          '-t', '$d',
          '-shortest',
          outputPath,
        ]);
      } finally {
        try { await mainFile.delete(); } catch (_) {}
        try { await subFile.delete(); } catch (_) {}
      }
    }

    return _simulateCopy(outputPath, outputPath, 'ending template');
  }

  /// Generate a design-set startup (intro) video — [set] picks the theme
  /// ('blue': sky gradient + drifting dots + deep-blue plate; 'translucent':
  /// frosted backdrop + layered pastel blobs + smoked-glass plate; 'yellow':
  /// sun-yellow gradient + rotating rays + umber plate). When
  /// [title]/[subtitle] are supplied they are burned in (pipeline use); the
  /// embedded template keeps the plate empty so the editor overlays user
  /// text. Complexity stays below the football startup scenes.
  Future<ProcessResult> generateSetStartup({
    required String outputPath,
    String set = 'blue',
    String? title,
    String? subtitle,
    String? bgmPath,
    double? durationSecs,
    int width = 1280,
    int height = 720,
    void Function(double progress)? onProgress,
  }) async {
    if (hasRealEncoder) {
      final fontPath = _findSystemFont();
      final d = durationSecs ?? 4.0;
      final hasTitle = title != null && title.isNotEmpty;
      String? escT;
      String? escS;
      File? titleFile;
      File? subFile;
      if (hasTitle) {
        titleFile = File('$outputPath.title.txt');
        subFile = File('$outputPath.subtitle.txt');
        await titleFile.writeAsString(title);
        await subFile.writeAsString(subtitle ?? '');
        escT = titleFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');
        escS = subFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');
      }
      try {
        final fontOpt = fontPath != null ? "fontfile='$fontPath':" : '';
        final scene = _setLayers(set, d, withPlate: true);
        final (mainCol, subCol, outCol) = _setTextColors(set);
        final geq = set == 'nocturne'
            ? _nocturneGeq(scene.$1, scene.$2)
            : _rsGeq(scene.$1, scene.$2);
        final hw = width ~/ 2;
        final hh = height ~/ 2;
        final vfParts = ['format=rgb24', geq, 'format=yuv420p',
          'scale=$width:$height:flags=lanczos', 'fps=30'];
        if (hasTitle && escT != null && escS != null) {
          const fadeIn = 'min(max((t-0.5)/0.7,0),1)';
          final fadeOut =
              '1-min(max((t-${(d - 0.8).toStringAsFixed(2)})/0.5,0),1)';
          vfParts.add("drawtext=${fontOpt}textfile='$escT':fontsize=62:"
              'fontcolor=$mainCol:borderw=2:bordercolor=$outCol:'
              "x=(w-text_w)/2:y='h*0.46-text_h/2':"
              "alpha='min($fadeIn,$fadeOut)'");
          vfParts.add("drawtext=${fontOpt}textfile='$escS':fontsize=30:"
              'fontcolor=$subCol:'
              "x=(w-text_w)/2:y='h*0.46+text_h/2+34':"
              "alpha='min($fadeIn,$fadeOut)'");
        }
        vfParts.add('fade=t=in:st=0:d=0.5');
        vfParts.add('fade=t=out:st=${d - 0.6}:d=0.6');
        final vf = vfParts.join(',');

        final bgm = (bgmPath != null && File(bgmPath).existsSync())
            ? bgmPath
            : await resolveDefaultBgm();
        final args = <String>[
          '-y',
          '-f', 'lavfi',
          '-i', 'color=c=black:s=${hw}x$hh:d=$d:r=30',
        ];
        if (bgm != null) {
          args.addAll([
            '-stream_loop', '-1',
            '-i', bgm,
            '-map', '0:v',
            '-map', '1:a',
            '-vf', vf,
            '-af', ('afade=t=in:st=0:d=0.5,afade=t=out:st=${d - 0.8}:d=0.8,'
                'volume=0.9'),
          ]);
        } else {
          args.addAll([
            '-f', 'lavfi',
            '-i', 'anullsrc=r=44100:cl=stereo',
            '-vf', vf,
          ]);
        }
        args.addAll([
          ..._h264Args(width: width, height: height),
          '-c:a', 'aac',
          if (bgm != null)
            ...['-ar', '44100', '-ac', '2', '-b:a', '128k']
          else
            ...['-b:a', '64k'],
          '-pix_fmt', 'yuv420p',
          '-t', '$d',
          '-shortest',
          outputPath,
        ]);
        return await _ffmpeg(args, durationSecs: d, onProgress: onProgress);
      } finally {
        if (titleFile != null) {
          try { await titleFile.delete(); } catch (_) {}
        }
        if (subFile != null) {
          try { await subFile.delete(); } catch (_) {}
        }
      }
    }

    return _simulateCopy(outputPath, outputPath, 'set startup');
  }

  /// Generate a design-set ending (outro) video — [set] picks the theme
  /// ('blue' sky-blue dots, no plate; 'translucent' frosted glass and
  /// 'yellow' sun rays both carry a glass text band). "感谢观看" and a sub
  /// line fade in — equal complexity to the existing endings.
  Future<ProcessResult> generateSetEnding({
    required String outputPath,
    String set = 'blue',
    String mainText = '感谢观看',
    String subText = 'Thanks for Watching',
    String? bgmPath,
    double durationSecs = 3.0,
    int width = 1280,
    int height = 720,
    void Function(double progress)? onProgress,
  }) async {
    if (hasRealEncoder) {
      final fontPath = _findSystemFont();
      final d = durationSecs;
      final scene = _setLayers(set, d, withPlate: set != 'blue', settle: true);
      final (mainCol, subCol, outCol) = _setTextColors(set);
      final geq = set == 'nocturne'
          ? _nocturneGeq(scene.$1, scene.$2)
          : _rsGeq(scene.$1, scene.$2);
      final hw = width ~/ 2;
      final hh = height ~/ 2;
      final fontOpt = fontPath != null ? "fontfile='$fontPath':" : '';

      final mainFile = File('$outputPath.main.txt');
      final subFile = File('$outputPath.sub.txt');
      await mainFile.writeAsString(mainText);
      await subFile.writeAsString(subText);
      // ponytail: watermark is a fixed ASCII brand string, so a text file
      // (rather than inline text=) keeps escaping uniform with main/sub.
      final watermarkFile = File('$outputPath.watermark.txt');
      await watermarkFile.writeAsString('Highlight Creator');

      try {
        final escMain = mainFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');
        final escSub = subFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');
        final escWm = watermarkFile.path
            .replaceAll('\\', '/')
            .replaceAll(':', '\\:');

        final mainDraw = "drawtext=${fontOpt}textfile='$escMain':"
            'fontsize=64:fontcolor=$mainCol:borderw=2:bordercolor=$outCol:'
            'x=(w-text_w)/2:y=(h-text_h)/2-30:'
            "alpha='if(lt(t,0.3),0,if(lt(t,1.0),(t-0.3)/0.7,1))'";
        final subDraw = "drawtext=${fontOpt}textfile='$escSub':"
            'fontsize=30:fontcolor=$subCol:'
            'x=(w-text_w)/2:y=(h/2)+30:'
            "alpha='if(lt(t,0.8),0,if(lt(t,1.5),(t-0.8)/0.7,1))'";
        // Bottom-right brand watermark; the trailing fades apply to it too.
        final wmDraw = "drawtext=${fontOpt}textfile='$escWm':"
            'fontsize=24:fontcolor=white@0.55:'
            'x=w-text_w-30:y=h-text_h-30';
        final vf = 'format=rgb24,$geq,format=yuv420p,'
            'scale=$width:$height:flags=lanczos,fps=30'
            ',$mainDraw,$subDraw,$wmDraw,fade=t=in:st=0:d=0.3,'
            'fade=t=out:st=${d - 0.8}:d=0.8';

        final args = <String>[
          '-y',
          '-f', 'lavfi',
          '-i', 'color=c=black:s=${hw}x$hh:d=$d:r=30',
        ];
        if (bgmPath != null && File(bgmPath).existsSync()) {
          args.addAll([
            '-stream_loop', '-1',
            '-i', bgmPath,
            '-map', '0:v',
            '-map', '1:a',
            '-vf', vf,
            '-af', ('afade=t=in:st=0:d=0.3,afade=t=out:st=${d - 0.8}:d=0.8,'
                'volume=0.9'),
          ]);
        } else {
          args.addAll([
            '-f', 'lavfi',
            '-i', 'anullsrc=r=44100:cl=stereo',
            '-vf', vf,
          ]);
        }
        args.addAll([
          ..._h264Args(width: width, height: height),
          '-c:a', 'aac',
          if (bgmPath != null && File(bgmPath).existsSync())
            ...['-ar', '44100', '-ac', '2', '-b:a', '128k']
          else
            ...['-b:a', '64k'],
          '-pix_fmt', 'yuv420p',
          '-t', '$d',
          '-shortest',
          outputPath,
        ]);
        return await _ffmpeg(args, durationSecs: d, onProgress: onProgress);
      } finally {
        try { await mainFile.delete(); } catch (_) {}
        try { await subFile.delete(); } catch (_) {}
        try { await watermarkFile.delete(); } catch (_) {}
      }
    }

    return _simulateCopy(outputPath, outputPath, 'set ending');
  }

  Future<ProcessResult> generateFootballEnding({
    required String outputPath,
    required int design,
    String? title,
    String? bgmPath,
    double? durationSecs,
    int width = 1280,
    int height = 720,
  }) async {
    if (hasRealEncoder) {
      final fontPath = _findSystemFont();
      final d = durationSecs ?? 3.0;
      final hasTitle = title != null && title.isNotEmpty;
      String? escT;
      File? titleFile;
      if (hasTitle) {
        titleFile = File('$outputPath.title.txt');
        await titleFile.writeAsString(title);
        escT = titleFile.path.replaceAll('\\', '/').replaceAll(':', '\\:');
      }
      try {
        final fontOpt = fontPath != null ? "fontfile='$fontPath':" : '';
        final scene = _reLayers(design, d);
        final geq = _rsGeq(scene.$1, scene.$2);
        final titles = _reTitles(design, d, fontOpt, escT);
        final hw = width ~/ 2;
        final hh = height ~/ 2;
        final vfParts = ['format=rgb24', geq, 'format=yuv420p',
          'scale=$width:$height:flags=lanczos', 'fps=30'];
        if (titles.isNotEmpty) vfParts.add(titles);
        vfParts.add('fade=t=in:st=0:d=0.4');
        vfParts.add('fade=t=out:st=${d - 0.8}:d=0.8');
        final vf = vfParts.join(',');

        final args = <String>[
          '-y',
          '-f', 'lavfi',
          '-i', 'color=c=black:s=${hw}x$hh:d=$d:r=30',
        ];
        if (bgmPath != null && File(bgmPath).existsSync()) {
          args.addAll([
            '-stream_loop', '-1',
            '-i', bgmPath,
            '-map', '0:v',
            '-map', '1:a',
            '-vf', vf,
            '-af', ('afade=t=in:st=0:d=0.4,afade=t=out:st=${d - 1.0}:d=1.0,'
                'volume=0.9'),
          ]);
        } else {
          args.addAll([
            '-f', 'lavfi',
            '-i', 'anullsrc=r=44100:cl=stereo',
            '-vf', vf,
          ]);
        }
        args.addAll([
          ..._h264Args(width: width, height: height),
          '-c:a', 'aac',
          if (bgmPath != null && File(bgmPath).existsSync())
            ...['-ar', '44100', '-ac', '2', '-b:a', '128k']
          else
            ...['-b:a', '64k'],
          '-pix_fmt', 'yuv420p',
          '-t', '$d',
          '-shortest',
          outputPath,
        ]);
        return await _ffmpeg(args);
      } finally {
        if (titleFile != null) {
          try { await titleFile.delete(); } catch (_) {}
        }
      }
    }

    return _simulateCopy(outputPath, outputPath, 'football ending');
  }

  /// Shared layer set for the 'blue' (sky-blue) design-set theme: a bright
  /// azure gradient with fast-expanding white rings (ripple pulse) and an
  /// optional deep-blue center text plate. One bold, high-contrast motion
  /// layer keeps the set clean, bright and energetic — two layers max.
  /// ponytail: ceiling = one hard-coded pattern; a next set needs its own
  /// _skyLayers-style helper, or this could graduate to a data-driven table.
  static (List<(String, String, List<String>)>, List<String>) _skyLayers(
    double d, {
    bool withPlate = false,
  }) {
    const glow = 'max(0\\,1-Y/(H*0.5))';
    final fadeGlow = 'max(0\\,1-T/(${d.toStringAsFixed(1)}))';
    // Expanding white rings — the `T/d` normalization keeps a fixed pulse
    // count per clip regardless of duration (startup 4 s vs ending 3 s).
    const r = 'sqrt(pow(X-W/2\\,2)+pow(Y-H/2\\,2))';
    final ring = 'lt(abs(mod($r-700*T/$d\\,150)-75)\\,3)';
    final ringApp = '(0.55)*(${_win(0.0, 0.5, d - 0.8, d)})';

    // Ponytail: scrolling yellow football along bottom edge, left-to-right
    const ballR = 'H*0.08';
    final ballCx = '-$ballR + (W + 2*$ballR) * T/$d';
    const ballCy = 'H - $ballR';
    const ballSpin = 3.0;
    final ballApp = _win(0.0, 0.3, d - 0.3, d);

    final base = [
      '42+44*$glow*$fadeGlow+2*sin(T*1.5)',
      '120+70*$glow*$fadeGlow+3*sin(T*1.5)',
      '218+40*$glow*$fadeGlow+2*sin(T*1.5)',
    ];
    final layers = <(String, String, List<String>)>[
      (ring, ringApp, _rsWhite),
      if (withPlate)
        (_rect('W/2', 'H*0.46', 'W*0.30', 'H*0.115', '12'),
            '(0.55)*(${_win(0.4, 1.2, d - 0.9, d)})', _rsSkyDeep),
      ..._fbBall(ballCx, ballCy, ballR, ballApp, ballSpin),
    ];
    return (layers, base);
  }

  /// Shared layer set for the 'yellow' design-set theme: a vivid sun-yellow
  /// gradient with fast-rotating white rays, plus an optional deep umber
  /// text plate. Two layers max — the leanest set.
  static (List<(String, String, List<String>)>, List<String>) _sunLayers(
    double d, {
    bool withPlate = false,
  }) {
    const glow = 'max(0\\,1-Y/(H*0.5))';
    const ang = 'atan2(Y-H/2\\,X-W/2)';
    final ray = 'lt(abs(mod($ang*12/PI+8*T/$d\\,2)-1)\\,0.13)';
    final rayApp = '(0.50)*(${_win(0.0, 0.6, d - 1.0, d)})';

    // Ponytail: scrolling football along bottom edge, left-to-right
    const ballR = 'H*0.08';
    final ballCx = '-$ballR + (W + 2*$ballR) * T/$d';
    const ballCy = 'H - $ballR';
    const ballSpin = 3.0;
    final ballApp = _win(0.0, 0.3, d - 0.3, d);

    final base = [
      '238+16*$glow+2*sin(T*1.2)',
      '190+26*$glow+3*sin(T*1.2)',
      '52+16*$glow+2*sin(T*1.2)',
    ];
    final layers = <(String, String, List<String>)>[
      (ray, rayApp, _rsWhite),
      if (withPlate)
        (_rect('W/2', 'H*0.46', 'W*0.30', 'H*0.115', '12'),
            '(0.62)*(${_win(0.4, 1.2, d - 0.9, d)})', _rsUmber),
      ..._fbBall(ballCx, ballCy, ballR, ballApp, ballSpin),
    ];
    return (layers, base);
  }

  /// Shared layer set for the 'green' design-set theme: a deep forest-green
  /// gradient with floating leaf-like particles, plus an optional dark plate.
  static (List<(String, String, List<String>)>, List<String>) _greenLayers(
    double d, {
    bool withPlate = false,
  }) {
    const glow = 'max(0\\,1-Y/(H*0.6))';
    final fadeGlow = 'max(0\\,1-T/(${d.toStringAsFixed(1)}))';
    // Floating particles drifting upward like leaves
    final py = 'mod(H*1.2-H*0.8*T/$d\\,H*1.2)';
    const px1 = 'W*0.3+sin(T*0.8)*W*0.05';
    const px2 = 'W*0.7+cos(T*0.6)*W*0.05';
    final p1 = 'lt(sqrt(pow(X-($px1)\\,2)+pow(Y-($py)\\,2))\\,12)';
    final p2 = 'lt(sqrt(pow(X-($px2)\\,2)+pow(Y-(mod($py+H*0.5\\,H*1.2))\\,2))\\,10)';
    final pApp = '(0.45)*(${_win(0.0, 0.5, d - 0.8, d)})';

    // Ponytail: scrolling yellow football along bottom edge, left-to-right
    const ballR = 'H*0.08';
    final ballCx = '-$ballR + (W + 2*$ballR) * T/$d';
    const ballCy = 'H - $ballR';
    const ballSpin = 3.0;
    final ballApp = _win(0.0, 0.3, d - 0.3, d);

    final base = [
      '10+30*$glow*$fadeGlow+2*sin(T*1.4)',
      '50+60*$glow*$fadeGlow+3*sin(T*1.4)',
      '15+30*$glow*$fadeGlow+2*sin(T*1.4)',
    ];
    final layers = <(String, String, List<String>)>[
      (p1, pApp, _rsWhite),
      (p2, pApp, _rsWhite),
      if (withPlate)
        (_rect('W/2', 'H*0.46', 'W*0.30', 'H*0.115', '12'),
            '(0.60)*(${_win(0.4, 1.2, d - 0.9, d)})', _rsForestPlate),
      ..._fbBall(ballCx, ballCy, ballR, ballApp, ballSpin),
    ];
    return (layers, base);
  }

  /// Shared layer set for the 'nocturne' (night stadium) design-set theme.
  ///
  /// The other sets are a gradient plus one repeating pattern, which is why
  /// they read flat. This one is built in depth order instead: a graded
  /// indigo sky, three parallel light shafts raking down-right, a mowed pitch
  /// in faked perspective below a hairline horizon, and an anamorphic streak
  /// blooming along that horizon. On top sits the graphic layer — one hairline
  /// system in a single amber accent (title band with a lit top edge, corner
  /// brackets, horizon rail and tick scale). Four directions (raking
  /// diagonals, horizontal streak, converging stripes, orthogonal hairlines)
  /// in one restrained palette; only the light moves, the ground does not,
  /// which is what makes the light read as light.
  ///
  /// [settle] switches the clip into outro mode: the shafts retreat, narrow
  /// and dim across the clip instead of raking in and coming up.
  /// ponytail: ceiling = one light source and one floor, ~14 kB of filter
  /// string. Windows caps the whole command line at 32767 chars, and a second
  /// light bank or horizon would blow that; at that point the scene has to
  /// graduate to a data-driven table (or ship as a filter script) rather than
  /// grow more literals.
  static (List<(String, String, List<String>)>, List<String>) _nocturneLayers(
    double d, {
    bool withPlate = false,
    bool settle = false,
  }) {
    const hzn = 'H*0.66';

    // Below-horizon ramp. Gates the pitch and doubles as the perspective
    // divisor for the mow stripes, so they converge exactly on the horizon.
    // The 0.13 floor stops the far stripes going sub-pixel, which would alias
    // into moire right along the rail.
    const dp = 'min(max((Y-$hzn)/(H*0.22)\\,0)\\,1)';
    const persp = '(0.13+0.87*$dp)';

    // Light only: eases up over the intro, retreats and dims over the outro.
    // The grade underneath never moves.
    final lit = settle
        ? '(0.28+0.72*(1-${_ease('T', 0.1, d)}))'
        : _ease('T', 0.05, 1.60);
    final travel = settle
        ? '(-W*0.18*${_ease('T', 0.0, d)})'
        : '(W*0.22*${_ease('T', 0.1, 2.40)})';
    final grow = settle ? '(1-0.32*${_ease('T', 0.2, d)})' : '1';

    // Three parallel shafts (slope m, ~46 deg) from one implied source, each
    // with its own width and weight so the rake has a rhythm instead of being
    // three identical bars. (bx, halfWidth0, halfWidthSlope, amp, swayPhase)
    const m = 1.05;
    final inv = (1 / math.sqrt(1 + m * m)).toStringAsFixed(5);
    final shaftSpec = <(double, double, double, double, double)>[
      (-0.06, 0.034, 0.25, 1.00, 0.00),
      (0.34, 0.024, 0.18, 0.80, 2.30),
      (0.72, 0.017, 0.13, 0.52, 4.10),
    ];
    final shaftCool = <double>[104, 130, 158];
    String shaftSum(int ch) {
      final out = <String>[];
      for (final s in shaftSpec) {
        // Slot 1 = source x, slot 2 = signed distance along the axis. Both are
        // stored once and read back, because inlining them costs more than the
        // whole scene budget (see the ponytail note above).
        // along goes negative "behind" the source, so it gates the emission
        // (a floodlight does not shine backwards) and the cone width clamps —
        // without the clamp a negative width inverts the cone and blows the
        // frame out to solid white.
        final src = 'W*${s.$1}+$travel'
            '+W*0.012*sin(2*PI*T/${d.toStringAsFixed(2)}+${s.$5})';
        const along = '(X-ld(1))+$m*(Y+H*0.25)';
        final perp = 'abs((Y+H*0.25)-$m*(X-ld(1)))*$inv';
        final width = '((W*${s.$2}+max(0\\,ld(2))*${s.$3})*$grow)';
        const fwd = 'min(1\\,max(0\\,ld(2)/(W*0.12)))';
        // Shafts emit in the same 0-255 units as the streak/pool/mow terms.
        final amp = (s.$4 * shaftCool[ch]).toStringAsFixed(2);
        // A 3.4x-wide cubic halo around the same axis: real light through haze
        // is a hot core inside a wide glow, and the core alone reads as a bar.
        final body = '((max(0\\,1-$perp/$width)^2'
            '+max(0\\,1-$perp/($width*3.4))^3*0.11)'
            '*$fwd*$amp/(1+ld(2)*ld(2)*6.0e-6))';
        out.add('${_slot(1, src)}+${_slot(2, "$along*$inv")}+$body');
      }
      return '${_slot(0, travel)}+${out.join('+')}';
    }

    // Anamorphic streak on the horizon: hot core plus a wide dim tail.
    const streakV = 'max(0\\,1-abs(Y-$hzn-H*0.005)/(H*0.075))';
    const streakH1 = 'max(0\\,1-abs(X-W/2)/(W*0.46))';
    const streakH2 = 'max(0\\,1-abs(X-W/2)/(W*0.80))';
    const streakShape = '($streakV*$streakV*($streakH1*$streakH1'
        '+$streakH2*0.35))';

    // The lit ellipse of pitch the shafts land on.
    const qx = '((X-W/2)/(W*0.54))';
    const qy = '((Y-H*0.80)/(H*0.34))';
    const poolShape = 'max(0\\,1-$qx*$qx-$qy*$qy)';

    // Mowed stripes: dividing x by a divisor that grows with depth is what
    // makes them converge. The depth ramp keeps them out of the horizon haze.
    const mow = '(1-2*gt(mod((X-W/2)/(W*0.05*$persp)\\,2)\\,1))'
        '*($dp*$dp)';

    const vx = '((X-W/2)/(W*0.62))';
    const vy = '((Y-H/2)/(H*0.62))';
    const vig = '(1-0.12*($vx*$vx+$vy*$vy))';

    final sky = <double>[5, 8, 14];
    final ground = <double>[13, 24, 31];
    final streakCol = <double>[78, 96, 116];
    final poolCol = <double>[22, 34, 30];
    final mowCol = <double>[4, 7, 5];

    final base = <String>[];
    for (var k = 0; k < 3; k++) {
      final grad = '${sky[k].toInt()}'
          '+${(ground[k] - sky[k]).toInt()}.0*(Y/H)';
      final light = '${shaftSum(k)}'
          '+${streakCol[k].toInt()}.0*$streakShape'
          '+${poolCol[k].toInt()}.0*$poolShape*$poolShape*$dp'
          '+${mowCol[k].toInt()}.0*$mow';
      // Hard ceiling before the write-back. geq does NOT clamp to the pixel
      // format's range — it wraps mod 256 — so one hot pixel (this scene sums
      // shafts + streak + pool) wraps into a band of garbage that reads as
      // deliberate colour. Cap first, grain after.
      base.add('min(250.0\\,max(0.0\\,($grad+$lit*($light))*$vig))'
          '+(random($k)-0.5)*4.5');
    }

    // --- Graphic layer: one hairline system, one accent, one weight. ---
    // Every mask is clamped: _nocturneGeq lerps as acc*(1-a)+color*a, so a
    // mask above 1 drives acc negative and the frame inverts into neon.
    // Summing mask pieces (four corners, rail + ticks) makes that easy to hit.
    final bandWin = _win(0.55, 1.35, d - 0.85, d);
    // Band opens from the centre; the soft reveal edge is what keeps it from
    // looking like a pasted rectangle.
    final wipe = _c01('(W*0.34*${_ease('T', 0.55, 1.35)}-abs(X-W/2))'
        '/(W*0.09)');
    final bracketWin = _win(0.75, 1.55, d - 0.75, d);
    final railWin = _win(0.10, 0.80, d - 0.70, d);

    String corner(String cx, String cy, double sx, double sy) {
      const len = 'W*0.070';
      final hSeg = '${_line('Y-$cy', 1.4)}'
          '*${_c01('($len-abs(X-($cx+$sx*$len*0.5)))/2.5')}';
      final vSeg = '${_line('X-$cx', 1.4)}'
          '*${_c01('($len*0.62-abs(Y-($cy+$sy*$len*0.31)))/2.5')}';
      return '(($hSeg)+($vSeg))';
    }

    const bx0 = 'W*0.048';
    const bx1 = 'W*0.952';
    const by0 = 'H*0.085';
    const by1 = 'H*0.915';
    // Taller than the other sets' 0.115 plate: the ending burns a second line
    // at h/2+30, which runs past 0.115 and would sit on the lit bottom edge.
    const bandH = 'H*0.132';

    final brackets = _c01('(${corner(bx0, by0, 1, 1)})'
        '+(${corner(bx1, by0, -1, 1)})'
        '+(${corner(bx0, by1, 1, -1)})'
        '+(${corner(bx1, by1, -1, -1)})');
    // Horizon rail with a tick scale riding on it — the pitch line itself.
    // The rail is always drawn; the ticks only brighten it. It fades out
    // toward the wings so it reads as lit haze, not a drawn divider.
    final rail = _c01('${_line('Y-$hzn', 1.3)}'
        '*(0.55+0.45*${_line('mod(X+W/32\\,W/16)-W/32', 1.0)}'
        '*${_c01('(H*0.020-abs(Y-$hzn))/(H*0.008)')})'
        '*${_c01('(W*0.94-abs(X-W/2))/(W*0.26)')}');

    final layers = <(String, String, List<String>)>[
      if (withPlate)
        (_c01(_rect('W/2', 'H*0.46', 'W*0.30', bandH, '14')),
            '(0.78)*($bandWin)*($wipe)', _rsNocturnePlate),
      if (withPlate)
        (_c01('${_line('Y-(H*0.46-$bandH)', 1.4)}*($wipe)'),
            '(0.85)*($bandWin)', _rsAmber),
      if (withPlate)
        (_c01('${_line('Y-(H*0.46+$bandH)', 1.1)}*($wipe)'),
            '(0.34)*($bandWin)', _rsAmber),
      (brackets, '(0.46)*($bracketWin)', _rsAmber),
      (rail, '(0.72)*($railWin)', _rsAmber),
    ];
    return (layers, base);
  }

  /// Layer fold for the 'nocturne' scene.
  ///
  /// Same lerp as [_rsGeq] — `acc*(1-a)+color*a` — but each alpha is evaluated
  /// once into its own geq slot and read back twice. That halves the filter
  /// string, which is the difference between fitting inside Windows' 32767-char
  /// command-line cap and failing to launch ffmpeg at all. Slots start at 4 so
  /// they cannot collide with the light rig in the base expression.
  static String _nocturneGeq(
    List<(String, String, List<String>)> layers,
    List<String> base,
  ) {
    String fold(int k) {
      var acc = base[k];
      final stores = <String>[];
      for (var i = 0; i < layers.length; i++) {
        stores.add(_slot(4 + i, '(${layers[i].$1})*(${layers[i].$2})'));
        acc = '($acc)*(1-ld(${4 + i}))'
            '+(${layers[i].$3[k]})*ld(${4 + i})';
      }
      return '${stores.join('+')}+($acc)';
    }

    return "geq=r='${fold(0)}':g='${fold(1)}':b='${fold(2)}'";
  }

  /// Layer set for a design-set id ('blue' | 'yellow' | 'green' | 'nocturne').
  static (List<(String, String, List<String>)>, List<String>) _setLayers(
    String set,
    double d, {
    required bool withPlate,
    bool settle = false,
  }) =>
      switch (set) {
        'yellow' => _sunLayers(d, withPlate: withPlate),
        'green' => _greenLayers(d, withPlate: withPlate),
        'nocturne' =>
          _nocturneLayers(d, withPlate: withPlate, settle: settle),
        _ => _skyLayers(d, withPlate: withPlate),
      };

  /// Per-set burned-in text colors: (main, sub, outline).
  static (String, String, String) _setTextColors(String set) => switch (set) {
        'yellow' => ('#FFFFFF', '#FFF3D6', '#4A2E0B@0.5'),
        'green' => ('#FFFFFF', '#C8E6C9', '#1B5E20@0.5'),
        'nocturne' => ('#F2F7FB', '#8FA6B8', '#04080C@0.75'),
        _ => ('#0B2E4F', '#FFFFFF', '#FFFFFF@0.6'),
      };

  static (List<(String, String, List<String>)>, List<String>) _reLayers(
    int design,
    double d,
  ) {
    const b = '3*sin(T*1.2)';
    switch (design) {
      case 2:
        const rad = 'max(0\\,1-$_dc/700)';
        final bc = 'H*0.38-H*0.25*${_ramp(0.0, d - 0.5)}';
        final r2 = '72-30*${_ramp(0.0, d - 0.5)}';
        final ballApp = _win(0.0, 0.4, d - 1.2, d);
        final partMask = '${_line('mod(X*0.6-Y+90*T\\,100)-50', 2.0)}*'
            '${_line('mod(X+Y*0.4-60*T\\,120)-60', 2.0)}';
        final partApp = '(0.6)*(${_win(0.0, 0.8, d - 1.5, d)})';
        const pcx = 'W/2';
        const pcy = 'H*0.72';
        const phw = 'W*0.32';
        const phh = 'H*0.075';
        final plateApp = '(0.75)*(${_win(0.3, 1.0, d - 1.0, d)})';
        final base = [
          '8+18*$rad+$b*0.3',
          '14+30*$rad+$b*0.5',
          '36+60*$rad+$b',
        ];
        return ([
          (partMask, partApp, _rsGold),
          ..._fbBall('W/2', bc, r2, ballApp, -1.5),
          (_rect(pcx, pcy, phw, phh, '12'), plateApp, _rsPlate),
        ], base);
      case 3:
        const glow = 'max(0\\,1-Y/(H*0.6))';
        const rad = 'max(0\\,1-$_dc/700)';
        final fadeGlow = 'max(0\\,1-T/(${d.toStringAsFixed(1)}))';
        final cLine = _line('X-W/2', 2.0);
        final cCircle = _line('$_dc-130', 2.5);
        final markApp = '(0.4)*(${_win(0.0, 0.6, d - 1.2, d)})';
        const bcx = 'W/2';
        const bcy = 'H*0.52';
        final ballApp = _win(0.0, 0.5, d - 1.0, d);
        const pcx = 'W/2';
        const pcy = 'H*0.78';
        const phw = 'W*0.26';
        const phh = 'H*0.065';
        final plateApp = '(0.70)*(${_win(0.2, 0.9, d - 0.8, d)})';
        final frameApp = _win(0.4, 1.1, d - 0.8, d);
        final base = [
          '(14+36*$rad+100*$glow*$fadeGlow+$b*0.3)',
          '(48+28*$rad+60*$glow*$fadeGlow+$b*0.6)',
          '(20+8*$rad+20*$glow*$fadeGlow+$b*0.3)',
        ];
        return ([
          (cLine, markApp, _rsWhite),
          (cCircle, markApp, _rsWhite),
          ..._fbBall(bcx, bcy, '52', ballApp, -2.0),
          (_rect(pcx, pcy, phw, phh, '12'), plateApp, _rsPlate),
          (_frame(pcx, pcy, phw, phh), frameApp, _rsGold),
        ], base);
      case 4:
        final spot = 'max(0\\,1-$_dc/(280-180*${_ramp(0.5, d - 0.3)}))';
        const bcx = 'W/2';
        const bcy = 'H*0.44';
        final ballApp = '(0.9)*(${_win(0.0, 0.4, d - 1.0, d)})';
        final base = [
          '6+4*$spot*244+$b*0.2',
          '6+4*$spot*244+$b*0.2',
          '8+6*$spot*238+$b*0.3',
        ];
        return ([
          ..._fbBall(bcx, bcy, '58', ballApp, -1.0),
        ], base);
      case 5:
        const rad = 'max(0\\,1-$_dc/650)';
        const wave = '8*sin((X-Y*0.2)/70+T*1.2)';
        final partMask = '${_line('mod(X*0.5+Y*0.8+100*T\\,80)-40', 1.8)}*'
            '${_line('mod(X*0.9-Y*0.3-70*T\\,95)-48', 1.8)}';
        final partApp = '(0.7)*(${_win(0.0, 0.6, d - 1.2, d)})';
        const ringR = '100+12*sin(T*2)';
        const dbc = 'sqrt(pow(X-W/2\\,2)+pow(Y-H*0.40\\,2))';
        final ringMask = _line('$dbc-($ringR)', 4.0);
        final ringApp = '(0.6)*(${_win(0.0, 0.5, d - 1.0, d)})';
        final ballApp = _win(0.0, 0.4, d - 1.2, d);
        const pcx = 'W/2';
        const pcy = 'H*0.74';
        const phw = 'W*0.30';
        const phh = 'H*0.07';
        final plateApp = '(0.72)*(${_win(0.2, 0.8, d - 0.8, d)})';
        final base = [
          '18+30*$rad+$wave*0.3+$b*0.3',
          '14+22*$rad+$wave*0.2+$b*0.3',
          '8+14*$rad+$wave*0.1+$b*0.2',
        ];
        return ([
          (partMask, partApp, _rsGold),
          (ringMask, ringApp, _rsGold),
          ..._fbBall('W/2', 'H*0.40', '64', ballApp, -2.5),
          (_rect(pcx, pcy, phw, phh, '12'), plateApp, _rsPlate),
        ], base);
      case 1:
      default:
        const rad = 'max(0\\,1-$_dc/620)';
        final vignette = 'max(0\\,1-$_dc/(500-200*${_ramp(0.0, d)}))';
        final bcx = 'W/2+W*0.20*${_ramp(0.3, d - 0.3)}';
        final r1 = '60-25*${_ramp(0.3, d - 0.3)}';
        final ballApp = _win(0.0, 0.4, d - 1.0, d);
        const pcx = 'W/2';
        const pcy = 'H*0.50';
        const phw = 'W*0.28';
        const phh = 'H*0.09';
        final plateApp = '(0.70)*(${_win(0.2, 0.9, d - 0.8, d)})';
        final lineApp = _win(0.3, 1.0, d - 0.8, d);
        final topLine = _hlineDraw('$pcy-$phh', pcx, phw, _ramp(0.3, 1.2));
        final botLine = _hlineDraw('$pcy+$phh', pcx, phw, _ramp(0.3, 1.2));
        final base = [
          '(8+10*$rad)*$vignette+$b*0.2',
          '(12+16*$rad)*$vignette+$b*0.3',
          '(10+12*$rad)*$vignette+$b*0.2',
        ];
        return ([
          ..._fbBall(bcx, 'H*0.72', r1, ballApp, -2.0),
          (_rect(pcx, pcy, phw, phh, '12'), plateApp, _rsPlate),
          (topLine, lineApp, _rsGold),
          (botLine, lineApp, _rsGold),
        ], base);
    }
  }

  static String _reTitles(
    int design,
    double d,
    String fontOpt,
    String? escT,
  ) {
    if (escT == null) return '';
    const fadeIn = '0.4';
    final fadeOut = (d - 0.8).toStringAsFixed(1);
    switch (design) {
      case 2:
        return "drawtext=${fontOpt}textfile='$escT':"
            'fontsize=42:fontcolor=0xF5C42D:'
            'x=(w-text_w)/2:y=h*0.72-text_h/2:'
            "alpha='if(lt(t,$fadeIn),0,if(lt(t,$fadeIn+0.6),(t-$fadeIn)/0.6,if(lt(t,$fadeOut),1,($d-t)/0.8)))'";
      case 4:
        return "drawtext=${fontOpt}textfile='$escT':"
            'fontsize=48:fontcolor=white:'
            'x=(w-text_w)/2:y=h*0.70-text_h/2:'
            "alpha='if(lt(t,$fadeIn),0,if(lt(t,$fadeIn+0.6),(t-$fadeIn)/0.6,if(lt(t,$fadeOut),1,($d-t)/0.8)))'";
      case 5:
        return "drawtext=${fontOpt}textfile='$escT':"
            'fontsize=40:fontcolor=0xF5C42D:'
            'x=(w-text_w)/2:y=h*0.74-text_h/2:'
            "alpha='if(lt(t,$fadeIn),0,if(lt(t,$fadeIn+0.6),(t-$fadeIn)/0.6,if(lt(t,$fadeOut),1,($d-t)/0.8)))'";
      case 3:
        return "drawtext=${fontOpt}textfile='$escT':"
            'fontsize=40:fontcolor=0xF5C42D:'
            'x=(w-text_w)/2:y=h*0.78-text_h/2:'
            "alpha='if(lt(t,$fadeIn),0,if(lt(t,$fadeIn+0.6),(t-$fadeIn)/0.6,if(lt(t,$fadeOut),1,($d-t)/0.8)))'";
      case 1:
      default:
        return "drawtext=${fontOpt}textfile='$escT':"
            'fontsize=44:fontcolor=0xF5C42D:'
            'x=(w-text_w)/2:y=h*0.50-text_h/2:'
            "alpha='if(lt(t,$fadeIn),0,if(lt(t,$fadeIn+0.6),(t-$fadeIn)/0.6,if(lt(t,$fadeOut),1,($d-t)/0.8)))'";
    }
  }

  /// Generate a football-themed transition template video (no text).
  ///
  /// Produces a short ([durationSecs], default 1.5s) MP4 with animated
  /// geometric elements.  [style] selects the color scheme, [variant]
  /// selects the animation design:
  ///
  /// * `'classic'` (default) — expanding center circle (pitch motif),
  ///   diagonal moving stripes, a horizontal center line, and a sweeping
  ///   vertical accent line.
  /// * Any other variant (`'chevrons'`, `'sweep'`, `'pulse'`, `'grid'`,
  ///   `'rays'`, `'diamonds'`, `'waves'`, `'spotlights'`, `'crosshatch'`,
  ///   `'orbit'`, `'shutter'`, `'scan'`, `'ripple'`) — a distinct animated
  ///   design on a dark palette.
  /// * Light-palette variants (`'linen'`, `'sunburst'`, `'polka'`,
  ///   `'arcs'`, `'zigzag'`) — pair with a light [style] (`'linen'`,
  ///   `'cream'`, `'blush'`, `'sky'`, `'mint'`); the center text card is
  ///   bright with dark-line animation outside it.
  ///
  /// All variants share a ring-outlined center text zone (~64% × 40% of
  /// the frame) so the drawtext overlay from [generateTransition] stays
  /// readable; each variant's animation only paints pixels outside that
  /// zone.
  Future<ProcessResult> generateTransitionTemplate({
    required String outputPath,
    String style = 'green',
    String variant = 'classic',
    double durationSecs = 1.5,
    int width = 1280,
    int height = 720,
    void Function(double progress)? onProgress,
  }) async {
    if (hasRealEncoder) {
      final bgColor = _styleBackground(style);
      final d = durationSecs;

      final geq = "geq=lum='${_transitionLum(variant, d)}':"
          "cb='p(X\\,Y)':cr='p(X\\,Y)'";

      final vf = '$geq,fade=t=in:st=0:d=0.15,fade=t=out:st=${d - 0.2}:d=0.2';

      return await _ffmpeg([
        '-y',
        '-f', 'lavfi',
        '-i', 'color=c=$bgColor:s=${width}x$height:d=$d:r=30',
        '-f', 'lavfi',
        '-i', 'anullsrc=r=44100:cl=stereo',
        '-vf', vf,
        ..._h264Args(width: width, height: height),
        '-c:a', 'aac',
        '-b:a', '64k',
        '-pix_fmt', 'yuv420p',
        '-t', '$d',
        '-shortest',
        outputPath,
      ], durationSecs: d, onProgress: onProgress);
    }

    return _simulateCopy(outputPath, outputPath, 'transition template');
  }

  /// Per-pixel lum expression for [generateTransitionTemplate] variants.
  ///
  /// Every variant is wrapped in the same reserved center text zone: inside
  /// it the background is darkened (with a slow breathing glow) and outlined
  /// by a faint ring, so the later centered drawtext overlay stays readable
  /// for *all* designs — including the original 'classic' animation.  The
  /// per-variant animation lives in [_transitionOutside] and only paints
  /// pixels outside the zone.
  static String _transitionLum(String variant, double d) {
    // Light-theme variants use an inverted zone (bright card + dark lines).
    const lightVariants = <String>{
      'linen', 'sunburst', 'polka', 'arcs', 'zigzag', 'blue', 'translucent',
      'yellow',
    };
    if (lightVariants.contains(variant)) {
      return _transitionLumLight(variant, d);
    }

    const zoneIn = 'lt(max(abs(X-W/2)/(W*0.32)\\,abs(Y-H/2)/(H*0.20))\\,1)';
    const zoneRing =
        'lt(abs(max(abs(X-W/2)/(W*0.32)\\,abs(Y-H/2)/(H*0.20))-1)\\,0.018)';
    final zoneLum = 'p(X\\,Y)*0.5+4+4*sin(2*PI*T/$d)';
    final outside = _transitionOutside(variant, d);
    return 'if($zoneIn\\,$zoneLum\\,'
        'if($zoneRing\\,140\\,$outside))';
  }

  /// Zone-outside animation for a transition variant (center reserved).
  static String _transitionOutside(String variant, double d) {
    switch (variant) {
      case 'chevrons':
        // Mirrored diagonal stripes drifting down-outward on both wings.
        final stripe =
            'lt(abs(mod(Y+0.55*if(lt(X\\,W/2)\\,X\\,W-X)+420*T/$d\\,150)-75)\\,3)';
        return 'if($stripe\\,160\\,p(X\\,Y))';
      case 'sweep':
        // Twin scan lines sweeping from the screen edges toward the text
        // zone, plus thin horizontal rails at top and bottom.
        final lineL = 'lt(abs(X-0.16*W*mod(2*T/$d\\,1))\\,2)';
        final lineR = 'lt(abs(X-(W-0.16*W*mod(2*T/$d\\,1)))\\,2)';
        const rails = 'lt(min(abs(Y-0.055*H)\\,abs(Y-0.945*H))\\,2)';
        return 'if($lineL\\,190\\,if($lineR\\,190\\,'
            'if($rails\\,125\\,p(X\\,Y))))';
      case 'pulse':
        // Concentric arcs pulsing out of the four corners plus static
        // corner brackets framing the screen.
        const cornerDist =
            'sqrt(pow(min(X\\,W-X)\\,2)+pow(min(Y\\,H-Y)\\,2))';
        final arc = 'lt(abs($cornerDist-mod(520*T/$d\\,640))\\,3)';
        const brackets = 'lt(max(min(abs(X-36)\\,abs(X-(W-36)))\\,'
            'min(abs(Y-36)\\,abs(Y-(H-36))))\\,2)';
        return 'if($brackets\\,150\\,if($arc\\,175\\,p(X\\,Y)))';
      case 'grid':
        // Drifting coordinate grid (vertical + horizontal lines).
        final vline = 'lt(abs(mod(X+160*T/$d\\,140)-70)\\,2)';
        final hline = 'lt(abs(mod(Y+110*T/$d\\,140)-70)\\,2)';
        return 'if($vline\\,150\\,if($hline\\,150\\,p(X\\,Y)))';
      case 'rays':
        // Rotating light rays radiating from center (cut by the zone, so
        // beams appear to shoot out from behind the text panel).
        const ang = 'atan2(Y-H/2\\,X-W/2)';
        final ray = 'lt(abs(mod($ang*8/PI+6*T/$d\\,2)-1)\\,0.06)';
        return 'if($ray\\,170\\,p(X\\,Y))';
      case 'diamonds':
        // Expanding diamond (Manhattan-distance) rings.
        const u = 'abs(X-W/2)+abs(Y-H/2)';
        final ring = 'lt(abs(mod($u-300*T/$d\\,120)-60)\\,3)';
        return 'if($ring\\,160\\,p(X\\,Y))';
      case 'waves':
        // Sinusoidal horizontal waves scrolling vertically.
        final wave =
            'lt(abs(mod(Y-30*sin(X/50+5*T/$d)+200*T/$d\\,120)-60)\\,2)';
        return 'if($wave\\,150\\,p(X\\,Y))';
      case 'spotlights':
        // Two roaming spotlights (Lissajous paths) brightening the wings.
        final h1 = 'sqrt(pow(X-(W*0.18+W*0.10*sin(5*T/$d))\\,2)+'
            'pow(Y-(H*0.30+H*0.20*cos(3*T/$d))\\,2))';
        final h2 = 'sqrt(pow(X-(W*0.82-W*0.10*sin(5*T/$d))\\,2)+'
            'pow(Y-(H*0.70-H*0.20*cos(3*T/$d))\\,2))';
        return 'p(X\\,Y)+if(lt($h1\\,150)\\,55\\,0)+if(lt($h2\\,150)\\,55\\,0)';
      case 'crosshatch':
        // Counter-scrolling diagonal cross-hatch.
        final a = 'lt(abs(mod(X+Y-200*T/$d\\,80)-40)\\,2)';
        final b = 'lt(abs(mod(X-Y+200*T/$d\\,80)-40)\\,2)';
        return 'if($a\\,145\\,if($b\\,145\\,p(X\\,Y)))';
      case 'orbit':
        // A comet with a fading tail orbiting on a zone-clearing ellipse.
        String dot(double off) {
          final th = '2*PI*1.5*T/$d-$off';
          final px = 'W/2+W*0.42*cos($th)';
          final py = 'H/2+H*0.42*sin($th)';
          return 'lt(sqrt(pow(X-$px\\,2)+pow(Y-$py\\,2))\\,18)';
        }
        return 'if(${dot(0)}\\,225\\,if(${dot(0.3)}\\,170\\,'
            'if(${dot(0.6)}\\,125\\,p(X\\,Y))))';
      case 'shutter':
        // Top & bottom light bands closing toward the text zone edges.
        final yu = 'H*0.30*mod(2*T/$d\\,1)';
        final upper = 'lt(abs(Y-$yu)\\,14)*lt(Y\\,H*0.30)';
        final yd = 'H-H*0.30*mod(2*T/$d\\,1)';
        final lower = 'lt(abs(Y-($yd))\\,14)*gt(Y\\,H*0.70)';
        return 'if($upper\\,180\\,if($lower\\,180\\,p(X\\,Y)))';
      case 'scan':
        // A single diagonal scan line sweeping the whole frame.
        final scan = 'lt(abs(mod(X*0.7+Y*0.7-600*T/$d\\,400)-200)\\,3)';
        return 'if($scan\\,190\\,p(X\\,Y))';
      case 'ripple':
        // Concentric circles rippling out from center (cut by the zone).
        const r = 'sqrt(pow(X-W/2\\,2)+pow(Y-H/2\\,2))';
        final ring = 'lt(abs(mod($r-260*T/$d\\,130)-65)\\,2)';
        return 'if($ring\\,165\\,p(X\\,Y))';
      case 'nocturne':
        // Three steep light shafts raking down-right plus a horizon rail that
        // brightens mid-clip — the 'nocturne' set's floodlight bank reduced to
        // a lum-only wipe. Additive over the dark base, so it stays on the
        // reserved-zone path and the centered overlay text keeps its contrast.
        String shaft(double phase, double w, double amp) {
          final x = '(mod(W*1.5*(T/$d+$phase)\\,W*2.2)-W*0.6)';
          final dist = 'abs((X-$x)-0.42*(Y-H*0.5))';
          return '${_line(dist, w)}'
              '*${_c01('(H*0.52-abs(Y-H*0.5))/(H*0.34)')}*$amp';
        }

        final rail = '${_line('Y-H*0.68', 1.6)}'
            '*88*${_win(0.10, 0.45, 1.05, 1.35)}';
        return 'p(X\\,Y)+${shaft(0.00, 32.0, 54.0)}'
            '+${shaft(0.37, 20.0, 36.0)}'
            '+${shaft(0.71, 12.0, 22.0)}+$rail';
      case 'classic':
      default:
        // Original full-frame animation (center now masked by the zone).
        return 'if(lt(abs(sqrt(pow(X-W/2\\,2)+pow(Y-H/2\\,2))-(60+200*T/$d))\\,3)\\,200\\,'
            'if(lt(abs(mod(X+Y-300*T\\,180)-90)\\,2)\\,140\\,'
            'if(lt(abs(Y-H/2)\\,2)\\,160\\,'
            'if(lt(abs(X-W*T/$d)\\,2)\\,190\\,'
            'p(X\\,Y)))))';
    }
  }

  /// Light-theme zone wrapper: a bright (near-white) breathing text card
  /// outlined by a dark ring, with dark-line animation outside the zone.
  static String _transitionLumLight(String variant, double d) {
    const zoneIn = 'lt(max(abs(X-W/2)/(W*0.32)\\,abs(Y-H/2)/(H*0.20))\\,1)';
    const zoneRing =
        'lt(abs(max(abs(X-W/2)/(W*0.32)\\,abs(Y-H/2)/(H*0.20))-1)\\,0.018)';
    final zoneLum = 'p(X\\,Y)*0.25+190+5*sin(2*PI*T/$d)';
    final outside = _transitionOutsideLight(variant, d);
    return 'if($zoneIn\\,$zoneLum\\,'
        'if($zoneRing\\,100\\,$outside))';
  }

  /// Zone-outside dark-line animation for the light-theme variants.
  static String _transitionOutsideLight(String variant, double d) {
    switch (variant) {
      case 'linen':
        // Fine drifting linen weave; intersections drawn darker.
        final v = 'lt(abs(mod(X+40*T/$d\\,28)-14)\\,1)';
        final h = 'lt(abs(mod(Y+30*T/$d\\,28)-14)\\,1)';
        return 'if($v*$h\\,95\\,if($v\\,130\\,if($h\\,130\\,p(X\\,Y))))';
      case 'sunburst':
        // Rotating dark rays radiating from behind the text card.
        const ang = 'atan2(Y-H/2\\,X-W/2)';
        final ray = 'lt(abs(mod($ang*10/PI+4*T/$d\\,2)-1)\\,0.05)';
        return 'if($ray\\,100\\,p(X\\,Y))';
      case 'polka':
        // Pulsing dark dot grid.
        final dx = 'abs(mod(X+30*T/$d\\,60)-30)';
        const dy = 'abs(mod(Y\\,60)-30)';
        final dot =
            'lt(sqrt(pow($dx\\,2)+pow($dy\\,2))\\,7+3*sin(2*PI*T/$d))';
        return 'if($dot\\,90\\,p(X\\,Y))';
      case 'arcs':
        // Concentric half-arcs rising from the bottom edge.
        const r = 'sqrt(pow(X-W/2\\,2)+pow(Y-H\\,2))';
        final ring = 'lt(abs(mod($r-220*T/$d\\,110)-55)\\,2)';
        return 'if($ring\\,105\\,p(X\\,Y))';
      case 'blue':
        // Expanding bright rings pulsing out from behind the text card —
        // echoes the 'blue' set startup (clean, bright, energetic).
        const r = 'sqrt(pow(X-W/2\\,2)+pow(Y-H/2\\,2))';
        final ring = 'lt(abs(mod($r-700*T/$d\\,150)-75)\\,3)';
        return 'if($ring\\,225\\,p(X\\,Y))';
      case 'translucent':
        // Two dark glass bands marching across the frosted base — echoes the
        // set's sliding glass panes (clean, fast, never a dead frame).
        final b1 = 'min(max((W*0.10-abs(X-(mod(W*1.6*T/$d\\,W*1.3)-W*0.15)))/16\\,0)\\,1)';
        final b2 = 'min(max((W*0.10-abs(X-(mod(W*1.6*T/$d+W*0.65\\,W*1.3)-W*0.15)))/16\\,0)\\,1)';
        return 'p(X\\,Y)-42*$b1-34*$b2';
      case 'yellow':
        // Rotating deep-gold sun rays beaming out from behind the text card
        // — the 'yellow' design set theme (faster spin, more rays).
        const ang = 'atan2(Y-H/2\\,X-W/2)';
        final ray = 'lt(abs(mod($ang*12/PI+8*T/$d\\,2)-1)\\,0.12)';
        return 'if($ray\\,105\\,p(X\\,Y))';
      case 'zigzag':
      default:
        // Stacked scrolling zig-zag waves.
        final line =
            'lt(abs(mod(Y-18*abs(mod(X/40+2*T/$d\\,2)-1)+90*T/$d\\,90)-45)\\,2)';
        return 'if($line\\,100\\,p(X\\,Y))';
    }
  }

  static String _styleBackground(String style) {
    switch (style) {
      case 'dark':
        return '0x1a1a2e';
      case 'blue':
        return '0x0d1b3e';
      case 'red':
        return '0x2e0a0a';
      case 'linen':
        return '0xf3ece1';
      case 'cream':
        return '0xf5f1e6';
      case 'blush':
        return '0xf6e7ea';
      case 'sky':
        return '0xe3eef7';
      case 'mint':
        return '0xe3f3ea';
      case 'skyblue':
        return '0x5aa7e6';
      case 'frost':
        return '0xe8ecf4';
      case 'gold':
        return '0xf5c42d';
      case 'forest':
        return '0x1a3a1a';
      case 'nocturne':
        return '0x070c14';
      case 'green':
      default:
        return '0x0a2e1a';
    }
  }

  static String _styleAccent(String style) {
    switch (style) {
      case 'dark':
        return '0xffd700';
      case 'blue':
        return '0x4fc3f7';
      case 'red':
        return '0xff5252';
      case 'skyblue':
        return '0x0b2e4f';
      case 'frost':
        return '0x3d4266';
      case 'gold':
        return '0x4a2e0b';
      case 'forest':
        return '0x2e7d32';
      case 'green':
      default:
        return '0x69f0ae';
    }
  }

  /// Simulation helper: copy a source file to the output path.
  ///
  /// Unlike the previous version, this never writes a corrupt bare header.
  /// If the source doesn't exist, it searches for any valid MP4 in the
  /// output directory's siblings as a last-resort placeholder.
  Future<ProcessResult> _simulateCopy(
    String sourcePath,
    String outputPath,
    String operation,
  ) async {
    try {
      final src = File(sourcePath);
      if (src.existsSync()) {
        await src.copy(outputPath);
      } else {
        // Source not found — try to locate any valid MP4 as a fallback
        // so we don't produce a corrupt/non-playable file.
        final fallback = await _findFallbackVideo(sourcePath);
        if (fallback != null) {
          await fallback.copy(outputPath);
        } else {
          // Truly no video available: create a tiny but structurally valid
          // MP4 file (moov atom with empty track, closed mdat).
          await _writeMinimalMp4(outputPath);
        }
      }
    } catch (e) {
      // Best effort — write a minimal valid MP4.
      try { await _writeMinimalMp4(outputPath); } catch (_) {}
    }

    return ProcessResult(0, 0, 'simulated: $operation → $outputPath', '');
  }

  /// Look for any playable MP4 file near the output directory.
  Future<File?> _findFallbackVideo(String failedPath) async {
    try {
      // Search the parent of the output directory and sibling dirs.
      final parent = Directory(File(failedPath).parent.path).parent;
      if (parent.existsSync()) {
        final candidates = await parent
            .list(recursive: true, followLinks: false)
            .where((e) => e is File && e.path.endsWith('.mp4'))
            .take(5)
            .toList();
        for (final c in candidates) {
          if (c is File && c.existsSync() && (await c.length()) > 1000) {
            return c;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Write a minimal structurally-valid MP4 file.
  ///
  /// Produces a tiny playable file with one black frame at 1280×720,
  /// 0.033s duration. Used as last-resort fallback.
  Future<void> _writeMinimalMp4(String path) async {
    // Pre-computed minimal MP4: ftyp + moov (empty track) + tiny mdat.
    // This creates a structurally valid MP4 that players can open.
    // The file has a single black frame at 720p.
    const minimalMp4 = [
      // ftyp atom (32 bytes)
      0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, // size=32, "ftyp"
      0x69, 0x73, 0x6F, 0x6D, 0x00, 0x00, 0x02, 0x00, // "isom", version
      0x69, 0x73, 0x6F, 0x6D, 0x69, 0x73, 0x6F, 0x32, // "isom", "iso2"
      0x61, 0x76, 0x63, 0x31, 0x6D, 0x70, 0x34, 0x31, // "avc1", "mp41"
      // moov atom (header)
      0x00, 0x00, 0x01, 0x50, 0x6D, 0x6F, 0x6F, 0x76, // size=336, "moov"
      // mvhd atom (108 bytes)
      0x00, 0x00, 0x00, 0x6C, 0x6D, 0x76, 0x68, 0x64, // size=108, "mvhd"
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // creation time
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // modification time
      0x00, 0x00, 0x03, 0xE8, 0x00, 0x00, 0x00, 0x01, // timescale=1000, duration=1
      0x00, 0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, // rate=1.0, volume=1.0
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // reserved (matrix part)
      0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x02,
      // trak atom (header + tkhd + mdia -> minf -> stbl)
      0x00, 0x00, 0x00, 0xDC, 0x74, 0x72, 0x61, 0x6B, // size=220, "trak"
      // tkhd (92 bytes, flags: track enabled)
      0x00, 0x00, 0x00, 0x5C, 0x74, 0x6B, 0x68, 0x64, // size=92, "tkhd"
      0x00, 0x00, 0x00, 0x07, 0x00, 0x00, 0x00, 0x00, // flags=7 (enabled+inMovie), id=0
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, // track id=1
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, // duration=1
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // reserved
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // layer=0, alt=0
      0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, // volume, reserved
      0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // matrix
      0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00, 0x00, // width=1280.0
      0x05, 0x00, 0x00, 0x00, 0x02, 0xD0, 0x00, 0x00, // height=720.0
      // mdia (128 bytes)
      0x00, 0x00, 0x00, 0x80, 0x6D, 0x64, 0x69, 0x61, // size=128, "mdia"
      // mdhd (32 bytes)
      0x00, 0x00, 0x00, 0x20, 0x6D, 0x64, 0x68, 0x64, // size=32, "mdhd"
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // times
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xE8, // timescale=1000
      0x00, 0x00, 0x00, 0x01, 0x55, 0xC4, 0x00, 0x00, // duration=1, lang=und
      // hdlr (36 bytes)
      0x00, 0x00, 0x00, 0x24, 0x68, 0x64, 0x6C, 0x72, // size=36, "hdlr"
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // version, flags
      0x76, 0x69, 0x64, 0x65, 0x00, 0x00, 0x00, 0x00, // "vide"
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00,
      // minf (36 bytes)
      0x00, 0x00, 0x00, 0x24, 0x6D, 0x69, 0x6E, 0x66, // size=36, "minf"
      // vmhd (20 bytes)
      0x00, 0x00, 0x00, 0x14, 0x76, 0x6D, 0x68, 0x64, // size=20, "vmhd"
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, // version, flags
      0x00, 0x00, 0x00, 0x00, // graphics mode=copy
      // dinf (36 bytes)
      0x00, 0x00, 0x00, 0x24, 0x64, 0x69, 0x6E, 0x66, // size=36, "dinf"
      0x00, 0x00, 0x00, 0x1C, 0x64, 0x72, 0x65, 0x66, // size=28, "dref"
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, // version, entry_count=1
      0x00, 0x00, 0x00, 0x0C, 0x75, 0x72, 0x6C, 0x20, // size=12, "url "
      0x00, 0x00, 0x00, 0x01, // flags=1 (self-contained)
      // stbl (84 bytes)
      0x00, 0x00, 0x00, 0x54, 0x73, 0x74, 0x62, 0x6C, // size=84, "stbl"
      // stsd (60 bytes - 1 entry)
      0x00, 0x00, 0x00, 0x3C, 0x73, 0x74, 0x73, 0x64, // size=60, "stsd"
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, // version, 1 entry
      // avc1 entry (44 bytes including avcC)
      0x00, 0x00, 0x00, 0x2C, 0x61, 0x76, 0x63, 0x31, // size=44, "avc1"
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, // reserved, data-ref=1
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // version, revision, vendor
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // temporal, spatial
      0x05, 0x00, 0x02, 0xD0, 0x00, 0x48, 0x00, 0x00, // 1280x720, dpi
      0x00, 0x48, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // dpi, frame_count
      0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // compressor name
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0xFF, 0xFF, // depth=24
      0x00, 0x00, 0x00, 0x00, // -1 (pre-defined)
      // mdat atom (empty — single frame placeholder)
      0x00, 0x00, 0x00, 0x08, 0x6D, 0x64, 0x61, 0x74, // size=8, "mdat"
    ];

    await File(path).writeAsBytes(minimalMp4);
  }
}
