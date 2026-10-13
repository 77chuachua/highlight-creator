import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/domain/entities/template_manifest.dart';
import 'package:highlight_creator/services/template_filter_policy.dart';

/// Thrown when the catalogue itself could not be obtained.
///
/// Separate from [TemplatePluginDownloadError] because the remedy differs:
/// this one is the user's connection or a moved file, not a template.
class TemplatePluginManifestError implements Exception {
  final String reason;

  /// True when a stale cached copy was served instead, so the UI can say so
  /// rather than pretending the catalogue is current.
  final bool servedFromCache;

  const TemplatePluginManifestError(this.reason,
      {this.servedFromCache = false});

  @override
  String toString() => reason;
}

/// Thrown when a template's filtergraph could not be fetched or failed its
/// integrity check.
class TemplatePluginDownloadError implements Exception {
  final String reason;

  /// The URL that failed, so the report names the thing to retry.
  final String url;

  const TemplatePluginDownloadError(this.reason, this.url);

  @override
  String toString() => '下载模板脚本失败 / Download failed\n$reason\n$url';
}

/// Thrown when the script downloaded cleanly but is not allowed to run.
///
/// Distinct from a download failure on purpose: nothing is wrong with the
/// network, the catalogue entry is asking for something this build refuses.
class TemplatePluginRejectedError implements Exception {
  final String reason;
  const TemplatePluginRejectedError(this.reason);

  @override
  String toString() => '模板脚本被拒绝 / Template script rejected\n$reason';
}

/// Thrown when an allowed script still failed to produce a video.
class TemplatePluginRenderError implements Exception {
  final String reason;

  /// Tail of ffmpeg's stderr, which is where the actual cause lives.
  final String ffmpegStderr;

  const TemplatePluginRenderError(this.reason, this.ffmpegStderr);

  @override
  String toString() =>
      '模板生成失败 / Template generation failed\n$reason\n$ffmpegStderr';
}

/// Fetches, validates and renders downloadable template plugins.
///
/// A plugin is an ffmpeg filtergraph plus render parameters, listed in a
/// manifest hosted on GitHub. Nothing about it is code: it is handed to the
/// same ffmpeg binary the built-in sets already use, after
/// [TemplateFilterPolicy] vets every filter in it.
///
/// Cache layout, all under the writable user profile so installed and MSIX
/// builds behave identically:
///   templates/manifest.json            last good catalogue
///   templates/plugins/<key>.ffscript   verified filtergraph
///   templates/plugins/<key>.mp4        rendered result
/// where `<key>` embeds the manifest revision, so publishing an update changes
/// the filename and invalidates the cache with no bookkeeping to get wrong.
class TemplatePluginService {
  final VideoProcessingService _vps;

  /// Overridable so a fork — or a test — can point at its own catalogue
  /// without touching code.
  ///
  /// The catalogue ships with this repository, served raw: every template's
  /// filtergraph sits next to it in `template_hub/`, and the `sizeBytes` /
  /// `sha256` it publishes are checked against the download. Adding a
  /// template is therefore a commit, not a release.
  static String manifestUrl =
      'https://raw.githubusercontent.com/77chuachua/highlight-creator/main/'
      'template_hub/template_list.json';

  /// Treat a cached catalogue as current for this long, so opening the editor
  /// does not hit the network on every rebuild.
  static const Duration cacheTtl = Duration(hours: 6);

  static const Duration _timeout = Duration(seconds: 20);

  static final String _pathSep = Platform.pathSeparator;
  static const int _maxManifestBytes = 1 << 20;

  TemplatePluginService(this._vps);

  /// `%USERPROFILE%\HighlightCreator\templates\plugins`
  static String get pluginDir {
    final dir = '${AppPaths.templatesDir}${Platform.pathSeparator}plugins';
    Directory(dir).createSync(recursive: true);
    return dir;
  }

  static String get _manifestCachePath =>
      '${AppPaths.templatesDir}${Platform.pathSeparator}manifest.json';

  // ---------------------------------------------------------------- manifest

  /// Load the catalogue, preferring the network and falling back to cache.
  ///
  /// Order matters on a first run after install: no cache *and* no network is a
  /// hard error the user must see, while a cache hit keeps the catalogue usable
  /// offline. A cache older than [cacheTtl] is still served when the network is
  /// down — a stale list beats an empty dialog.
  Future<TemplateManifest> loadManifest() async {
    final cached = _readCachedManifest();
    final fresh =
        cached != null && DateTime.now().difference(cached.$2) < cacheTtl;
    if (fresh) return cached.$1;

    try {
      final body = await _httpGetText(manifestUrl, cap: _maxManifestBytes);
      final manifest = TemplateManifest.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
      try {
        Directory(AppPaths.templatesDir).createSync(recursive: true);
        File(_manifestCachePath).writeAsStringSync(body);
      } catch (_) {
        // A read-only profile must not fail the load; the cache is an
        // optimisation, not a requirement.
      }
      return manifest;
    } on TemplateManifestFormatException catch (e) {
      // Reachable but wrong. A stale good copy is more useful than an error,
      // but only if we have one.
      if (cached != null) return cached.$1;
      throw TemplatePluginManifestError(
        '模板清单格式错误 / Template manifest is malformed\n$e',
        servedFromCache: true,
      );
    } on TemplatePluginDownloadError catch (e) {
      if (cached != null) return cached.$1;
      throw TemplatePluginManifestError(
        '无法加载模板清单 / Cannot load template manifest\n${e.reason}',
      );
    }
  }

  (TemplateManifest, DateTime)? _readCachedManifest() {
    try {
      final f = File(_manifestCachePath);
      if (!f.existsSync()) return null;
      final manifest = TemplateManifest.fromJson(
        jsonDecode(f.readAsStringSync()) as Map<String, dynamic>,
      );
      return (manifest, f.lastModifiedSync());
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ script

  /// Path of the verified filtergraph for [spec], downloading it if needed.
  ///
  /// Idempotent: a cached script is reused only when it still matches what the
  /// manifest promises, so a corrupted or tampered cache entry is re-fetched
  /// instead of trusted.
  Future<String> ensureScript(
    RemoteTemplateSpec spec, {
    void Function(double progress)? onProgress,
  }) async {
    final cached = File(_scriptPath(spec));
    if (await _matchesManifest(cached, spec)) {
      onProgress?.call(1);
      return cached.path;
    }

    onProgress?.call(0);
    final bytes =
        await _httpGetBytes(spec.script.url, cap: spec.script.sizeBytes);
    if (bytes.length != spec.script.sizeBytes) {
      throw TemplatePluginDownloadError(
        'size mismatch: manifest promised ${spec.script.sizeBytes} bytes, '
        'got ${bytes.length}',
        spec.script.url,
      );
    }
    final sha = sha256.convert(bytes).toString();
    if (spec.script.sha256 != null && sha != spec.script.sha256) {
      throw TemplatePluginDownloadError(
        'integrity check failed — the download does not match the manifest.\n'
        '  expected sha256 ${spec.script.sha256}\n'
        '  actual   sha256 $sha\n'
        'It may be corrupted, or the catalogue may have been tampered with.',
        spec.script.url,
      );
    }

    final text = utf8.decode(bytes, allowMalformed: true);
    final violation = TemplateFilterPolicy.validate(text);
    if (violation != null) {
      throw TemplatePluginRejectedError(
        'template "${spec.name}" (${spec.id}): $violation',
      );
    }

    // Written only after validation: a rejected script never touches disk.
    cached.writeAsBytesSync(bytes);
    onProgress?.call(1);
    return cached.path;
  }

  /// A cached script counts only when it matches the manifest on every check
  /// the manifest actually specifies — size always, hash when given.
  Future<bool> _matchesManifest(File f, RemoteTemplateSpec spec) async {
    if (!f.existsSync()) return false;
    if (await f.length() != spec.script.sizeBytes) return false;
    final want = spec.script.sha256;
    if (want == null) return true;
    return sha256.convert(await f.readAsBytes()).toString() == want;
  }

  String _scriptPath(RemoteTemplateSpec spec) =>
      '$pluginDir$_pathSep${spec.cacheKey}.ffscript';

  // ------------------------------------------------------------------ render

  /// Render [spec] to an mp4 and return its path.
  ///
  /// Returns the cached video when one exists for this exact revision, so
  /// repeat previews are free. Throws [TemplatePluginRenderError] when ffmpeg
  /// refuses or produces nothing — never a silent placeholder, for the same
  /// reason the built-in generators now refuse to run without ffmpeg.
  Future<String> render(
    RemoteTemplateSpec spec, {
    void Function(double progress)? onProgress,
    void Function(double progress)? onScriptProgress,
  }) async {
    final outPath = '$pluginDir$_pathSep${spec.cacheKey}.mp4';
    final outFile = File(outPath);
    if (outFile.existsSync() && await outFile.length() > 1024) {
      onProgress?.call(1);
      return outPath;
    }

    if (!await VideoProcessingService.isFfmpegAvailable()) {
      throw const TemplatePluginRenderError(
        'ffmpeg.exe not found — cannot render a template plugin. '
            'Put it next to highlight_creator.exe or on PATH.',
        '',
      );
    }

    final scriptPath = await ensureScript(spec, onProgress: onScriptProgress);
    // Trimmed because the script is handed to ffmpeg as one argument; a stray
    // trailing newline is harmless but a stray interior one is not (and
    // TemplateFilterPolicy has already rejected that case).
    final graph = File(scriptPath).readAsStringSync().trim();
    final r = spec.render;

    // geq runs at half resolution then scales up, matching the built-in
    // generators: full-res geq is ~4x the work for a difference nobody can see
    // on a soft gradient.
    final hw = r.width ~/ 2;
    final hh = r.height ~/ 2;

    final args = <String>[
      '-y',
      '-f',
      'lavfi',
      '-i',
      'color=c=black:s=${hw}x$hh:d=${r.durationSecs}:r=30',
    ];
    final bgm = await VideoProcessingService.resolveDefaultBgm();
    final useBgm = r.withBgm && bgm != null;
    if (useBgm) {
      args.addAll(['-stream_loop', '-1', '-i', bgm]);
    } else {
      args.addAll(['-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo']);
    }
    args.addAll([
      '-map',
      '0:v',
      '-map',
      '1:a',
      '-vf',
      graph,
      '-t',
      '${r.durationSecs}',
    ]);
    if (useBgm) {
      final fadeOut = (r.durationSecs - 0.6).clamp(0.0, r.durationSecs);
      args.addAll([
        '-af',
        'afade=t=in:st=0:d=0.4,afade=t=out:st=$fadeOut:d=0.6,volume=0.9',
        '-c:a',
        'aac',
        '-b:a',
        '128k',
      ]);
    } else {
      args.addAll(['-c:a', 'aac', '-b:a', '64k']);
    }
    args.addAll([
      '-c:v',
      'libopenh264',
      '-b:v',
      '${(r.width * r.height * 30 * 0.15 / 1000).round().clamp(1000, 120000)}k',
      '-pix_fmt',
      'yuv420p',
      '-shortest',
      outPath,
    ]);

    onProgress?.call(0.1);
    final res = await _vps.runFfmpeg(
      args,
      durationSecs: r.durationSecs,
      onProgress: (p) => onProgress?.call(0.1 + p * 0.9),
    );

    if (res.exitCode != 0 ||
        !outFile.existsSync() ||
        await outFile.length() <= 1024) {
      // A partial file would satisfy the cache check on the next click and look
      // like a success, so remove it before reporting.
      try {
        if (outFile.existsSync()) outFile.deleteSync();
      } catch (_) {}
      throw TemplatePluginRenderError(
        'ffmpeg exited with code ${res.exitCode}.',
        _tail(res.stderr),
      );
    }
    onProgress?.call(1);
    return outPath;
  }

  /// Forget a plugin's cached script and video so the next click re-fetches.
  void invalidate(String cacheKey) {
    for (final ext in ['.mp4', '.ffscript']) {
      try {
        final f = File('$pluginDir$_pathSep$cacheKey$ext');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  /// Drop every cached catalogue and plugin. Exposed for a "reset" affordance.
  void invalidateAll() {
    try {
      final dir = Directory(pluginDir);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
    try {
      final f = File(_manifestCachePath);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  // -------------------------------------------------------------------- http

  Future<List<int>> _httpGetBytes(String url, {required int cap}) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(_timeout);
      req.headers.set(HttpHeaders.acceptHeader, '*/*');
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        throw TemplatePluginDownloadError(
            'server returned HTTP ${res.statusCode}', url);
      }
      final builder = BytesBuilder(copy: false);
      // Read incrementally so a hostile or broken endpoint cannot make us
      // buffer whatever it likes: the cap is enforced as bytes arrive.
      await for (final chunk in res) {
        builder.add(chunk);
        if (builder.length > cap) {
          throw TemplatePluginDownloadError(
              'response exceeds the expected size (>$cap bytes)', url);
        }
      }
      return builder.takeBytes();
    } on TemplatePluginDownloadError {
      rethrow;
    } on TimeoutException {
      throw TemplatePluginDownloadError(
          'timed out after ${_timeout.inSeconds}s', url);
    } on SocketException catch (e) {
      throw TemplatePluginDownloadError('network error: ${e.message}', url);
    } on HandshakeException catch (e) {
      throw TemplatePluginDownloadError('TLS error: ${e.message}', url);
    } on FormatException catch (e) {
      throw TemplatePluginDownloadError('bad URL: ${e.message}', url);
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _httpGetText(String url, {required int cap}) async =>
      utf8.decode(await _httpGetBytes(url, cap: cap), allowMalformed: true);

  static String _tail(String stderr, [int lines = 6]) {
    final kept = stderr
        .trim()
        .split(RegExp(r'\r?\n'))
        .where((l) => l.trim().isNotEmpty)
        .toList();
    if (kept.isEmpty) return '(ffmpeg produced no diagnostics)';
    return kept.sublist(kept.length - lines).join('\n');
  }
}
