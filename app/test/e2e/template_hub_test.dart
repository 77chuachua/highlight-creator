// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/domain/entities/template_manifest.dart';
import 'package:highlight_creator/services/template_filter_policy.dart';
import 'package:highlight_creator/services/template_plugin_service.dart';

/// The published catalogue in `template_hub/` is the online template feature's
/// only input, and the app never reads it at build time — so nothing in the app
/// would notice it going stale. Two checks, because they fail for different
/// reasons:
///
/// 1. every catalogue entry is compared against the `.ffscript` committed
///    beside it — the failure being a script edited without refreshing
///    `sizeBytes`/`sha256`, which ships a card that can only fail on the
///    user's machine;
/// 2. the whole pipeline runs over that directory served on loopback (the same
///    bytes GitHub serves raw): catalogue parse -> download -> size + hash
///    check -> filter policy -> ffmpeg render at the promised resolution.
void main() {
  late HttpServer server;
  late Directory hub;
  late Directory sandbox;
  late VideoProcessingService vps;
  late String? ffmpegPath;
  late String realManifestUrl;
  late String realBaseDir;

  setUpAll(() async {
    ffmpegPath = await VideoProcessingService.findFfmpeg();
    vps = VideoProcessingService(ffmpegPath: ffmpegPath);
    print('ffmpeg: ${ffmpegPath ?? "NOT FOUND (render test will skip)"}');
    realManifestUrl = TemplatePluginService.manifestUrl;
    realBaseDir = AppPaths.baseDir;
    hub = _findHub();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final name =
          req.uri.pathSegments.isEmpty ? '' : req.uri.pathSegments.last;
      final f = File('${hub.path}${Platform.pathSeparator}$name');
      if (name.isEmpty || !f.existsSync()) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        return;
      }
      var bytes = f.readAsBytesSync();
      if (name == 'template_list.json') {
        // The published catalogue names raw.githubusercontent.com, which a test
        // must not depend on: re-point each script URL at this server, leaving
        // every other field — size, hash, render — exactly as published.
        final doc = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        for (final t in doc['templates'] as List) {
          final script = (t as Map<String, dynamic>)['script']
              as Map<String, dynamic>;
          final file = (script['url'] as String).split('/').last;
          script['url'] = 'http://127.0.0.1:${server.port}/$file';
        }
        bytes = utf8.encode(jsonEncode(doc));
      }
      req.response.headers.contentType = ContentType.json;
      req.response.add(bytes);
      await req.response.close();
    });
  });

  tearDownAll(() async {
    await server.close(force: true);
    TemplatePluginService.manifestUrl = realManifestUrl;
    AppPaths.overrideBaseDir = realBaseDir;
  });

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('hl_hub_test');
    AppPaths.overrideBaseDir = sandbox.path;
    TemplatePluginService.manifestUrl =
        'http://127.0.0.1:${server.port}/template_list.json';
  });

  tearDown(() {
    AppPaths.overrideBaseDir = realBaseDir;
    try {
      sandbox.deleteSync(recursive: true);
    } catch (_) {}
  });

  TemplatePluginService svc() => TemplatePluginService(vps);

  test('every catalogue entry matches the script committed beside it', () {
    final manifest = TemplateManifest.fromJson(
      jsonDecode(File('${hub.path}${Platform.pathSeparator}template_list.json')
          .readAsStringSync()) as Map<String, dynamic>,
    );
    expect(manifest.schemaVersion, 1);
    expect(manifest.templates.map((t) => t.id).toSet(),
        {'aurora-startup', 'aurora-ending', 'aurora-transition'});
    expect(manifest.templates.map((t) => t.type).toSet(),
        {TemplateType.startup, TemplateType.ending, TemplateType.transition});

    for (final spec in manifest.templates) {
      expect(spec.script.url, contains('/template_hub/'), reason: spec.id);
      final name = spec.script.url.split('/').last;
      final f = File('${hub.path}${Platform.pathSeparator}$name');
      expect(f.existsSync(), isTrue,
          reason: '${spec.id} points at $name, which is not committed');
      final bytes = f.readAsBytesSync();
      expect(spec.script.sizeBytes, bytes.length,
          reason: 'sizeBytes is stale for ${spec.id}');
      expect(spec.script.sha256, sha256.convert(bytes).toString(),
          reason: 'sha256 is stale for ${spec.id}');

      final text = utf8.decode(bytes);
      expect(TemplateFilterPolicy.validate(text), isNull, reason: spec.id);
      expect(text.length, lessThan(TemplateFilterPolicy.maxGraphChars),
          reason: '${spec.id} must fit on the ffmpeg command line');
    }
  });

  test('every published template downloads, verifies and renders', () async {
    if (ffmpegPath == null) return;
    final m = await svc().loadManifest();
    for (final spec in m.templates) {
      await svc().ensureScript(spec);
      final path = await svc().render(spec);
      expect(File(path).lengthSync(), greaterThan(1024), reason: spec.id);
      final res = await VideoProcessingService.probeResolution(path);
      if (res != null) {
        expect(res.$1, spec.render.width, reason: spec.id);
        expect(res.$2, spec.render.height, reason: spec.id);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

/// Walk up from the package directory (tests run with `app/` as cwd) to the
/// repository root, where the published catalogue lives.
Directory _findHub() {
  var dir = Directory.current;
  while (true) {
    final candidate =
        Directory('${dir.path}${Platform.pathSeparator}template_hub');
    if (File('${candidate.path}${Platform.pathSeparator}template_list.json')
        .existsSync()) {
      return candidate;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError('template_hub/ not found above ${Directory.current.path}');
}
