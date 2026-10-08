// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/services/template_plugin_service.dart';

/// End-to-end plugin pipeline against a real HTTP server and the real ffmpeg:
/// load catalogue -> download script -> verify hash -> validate filter policy
/// -> render -> cache.
///
/// The point of the test is the *error separation* the feature promises: a dead
/// network, a tampered download, a forbidden filter and a script ffmpeg refuses
/// are four different failures and must not collapse into one another.
void main() {
  late HttpServer server;
  late Directory sandbox;
  late VideoProcessingService service;
  late String? ffmpegPath;
  late String realManifestUrl;
  late String realBaseDir;

  /// graph -> what the fake CDN serves for that path
  final routes = <String, String>{};
  var requestCount = 0;

  /// Serves whatever the test put in `routes`; each request bumps the counter
  /// so "did this hit the network?" is answerable.
  Future<void> serveForever() async {
    await for (final req in server) {
      requestCount++;
      final body = routes[req.uri.path];
      if (body == null) {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
        continue;
      }
      req.response.headers.contentType = ContentType.text;
      req.response.write(body);
      await req.response.close();
    }
  }

  const goodGraph = 'format=rgb24,'
      "geq=r='30+40*(X/W)':g='40+60*(Y/H)':b='70+80*(X/W)',"
      'format=yuv420p,scale=320:180,fps=30,fade=t=in:st=0:d=0.2';

  String sha256Hex(String s) => sha256.convert(utf8.encode(s)).toString();

  setUpAll(() async {
    ffmpegPath = await VideoProcessingService.findFfmpeg();
    service = VideoProcessingService(ffmpegPath: ffmpegPath);
    print('ffmpeg: ${ffmpegPath ?? "NOT FOUND (render tests will skip)"}');

    realManifestUrl = TemplatePluginService.manifestUrl;
    realBaseDir = AppPaths.baseDir;

    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(serveForever());
  });

  tearDownAll(() async {
    await server.close(force: true);
    TemplatePluginService.manifestUrl = realManifestUrl;
    AppPaths.overrideBaseDir = realBaseDir;
  });

  setUp(() {
    requestCount = 0;
    routes.clear();
    sandbox = Directory.systemTemp.createTempSync('hl_plugin_test');
    AppPaths.overrideBaseDir = sandbox.path;
    TemplatePluginService.manifestUrl =
        'http://127.0.0.1:${server.port}/manifest.json';
  });

  tearDown(() {
    AppPaths.overrideBaseDir = realBaseDir;
    try {
      sandbox.deleteSync(recursive: true);
    } catch (_) {}
  });

  void serveScript(String name, String graph) =>
      routes['/$name'] = '$graph\n'; // trailing newline, as a repo file has

  void serveManifest(List<Map<String, dynamic>> templates) =>
      routes['/manifest.json'] = jsonEncode({
        'schemaVersion': 1,
        'updatedAt': '2026-10-04',
        'templates': templates,
      });

  /// Force the next `loadManifest` to refetch, without touching the plugin
  /// cache — otherwise a freshly published revision would be hidden by the
  /// catalogue TTL and the test would prove nothing.
  void expireCatalogue() {
    final f = File('${sandbox.path}${Platform.pathSeparator}templates'
        '${Platform.pathSeparator}manifest.json');
    if (f.existsSync()) f.deleteSync();
  }

  Map<String, dynamic> spec({
    String id = 'neon',
    String script = 'neon.ffscript',
    String? graph = goodGraph,
    String type = 'startup',
    String revision = 'r1',
    bool withHash = true,
    Map<String, dynamic>? render,
  }) {
    if (graph != null) serveScript(script, graph);
    // Hash and size describe the bytes actually served, trailing newline
    // included — the manifest makes promises about the wire, not about the
    // trimmed graph.
    final served = graph == null ? '' : '$graph\n';
    return {
      'id': id,
      'name': 'Neon $id',
      'type': type,
      'author': 'tester',
      'script': {
        'url': 'http://127.0.0.1:${server.port}/$script',
        if (withHash) 'sha256': sha256Hex(served),
        'sizeBytes': served.length,
        'revision': revision,
      },
      'render': render ?? {'durationSecs': 0.6, 'width': 320, 'height': 180},
    };
  }

  TemplatePluginService newService() => TemplatePluginService(service);

  group('manifest loading', () {
    test('loads and parses a catalogue', () async {
      serveManifest([spec()]);
      final m = await newService().loadManifest();
      expect(m.templates, hasLength(1));
      expect(m.templates.single.id, 'neon');
    });

    test('an unreachable catalogue with no cache is a manifest error',
        () async {
      TemplatePluginService.manifestUrl = 'http://127.0.0.1:1/manifest.json';
      expect(
        newService().loadManifest,
        throwsA(isA<TemplatePluginManifestError>()
            .having((e) => e.servedFromCache, 'servedFromCache', isFalse)),
      );
    });

    test('a malformed catalogue names the offending entry', () async {
      routes['/manifest.json'] = jsonEncode({
        'schemaVersion': 1,
        'templates': [
          {'id': 'x'}
        ]
      });
      expect(
        newService().loadManifest,
        throwsA(isA<TemplatePluginManifestError>()
            .having((e) => e.reason, 'reason', contains('missing required'))),
      );
    });

    test('a second load is served from cache without hitting the network',
        () async {
      serveManifest([spec()]);
      final svc = newService();
      await svc.loadManifest();
      final after = requestCount;
      await svc.loadManifest();
      expect(requestCount, after, reason: 'cached catalogue must not refetch');
    });

    test('a dead network still yields the cached catalogue', () async {
      serveManifest([spec()]);
      await newService().loadManifest();
      // Point at a dead port; the cache should carry the load.
      TemplatePluginService.manifestUrl = 'http://127.0.0.1:1/manifest.json';
      final m = await newService().loadManifest();
      expect(m.templates, hasLength(1));
    });
  });

  group('download', () {
    test('fetches, verifies and caches the script', () async {
      serveManifest([spec()]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;
      final path = await svc.ensureScript(s);
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsStringSync().trim(), goodGraph);
    });

    test('a hash mismatch is a DOWNLOAD error and writes nothing', () async {
      serveManifest([
        {
          ...spec(),
          'script': {
            'url': 'http://127.0.0.1:${server.port}/neon.ffscript',
            // Correct size, wrong hash: the case that would otherwise render
            // someone else's template under this template's name.
            'sha256': 'f' * 64,
            'sizeBytes': goodGraph.length + 1,
            'revision': 'r1',
          },
        },
      ]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;
      await expectLater(
        svc.ensureScript(s),
        throwsA(isA<TemplatePluginDownloadError>().having((e) => e.toString(),
            'message', contains('integrity check failed'))),
      );
      final dir = Directory(TemplatePluginService.pluginDir);
      expect(
          dir.listSync().where((f) => f.path.endsWith('.ffscript')), isEmpty);
    });

    test('a size mismatch is a download error', () async {
      serveManifest([
        {
          ...spec(),
          'script': {
            'url': 'http://127.0.0.1:${server.port}/neon.ffscript',
            'sizeBytes': 99999,
            'revision': 'r1',
          },
        },
      ]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;
      await expectLater(
          svc.ensureScript(s), throwsA(isA<TemplatePluginDownloadError>()));
    });

    test('HTTP 404 is a download error naming the status', () async {
      serveManifest([
        {
          ...spec(graph: null),
          'script': {
            'url': 'http://127.0.0.1:${server.port}/missing.ffscript',
            'sizeBytes': 10,
            'revision': 'r1',
          },
        },
      ]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;
      await expectLater(
        svc.ensureScript(s),
        throwsA(isA<TemplatePluginDownloadError>()
            .having((e) => e.reason, 'reason', contains('404'))),
      );
    });

    test('a cached script is reused, not refetched', () async {
      serveManifest([spec()]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;
      await svc.ensureScript(s);
      final after = requestCount;
      await svc.ensureScript(s);
      expect(requestCount, after, reason: 'verified script must be reused');
    });

    test('a new revision invalidates the cache', () async {
      serveManifest([spec(revision: 'r1')]);
      final svc = newService();
      final first = (await svc.loadManifest()).templates.single;
      final p1 = await svc.ensureScript(first);

      serveManifest([
        spec(
          revision: 'r2',
          script: 'neon2.ffscript',
          graph: 'fps=30,fade=t=out',
        ),
      ]);
      expireCatalogue();
      final second = (await svc.loadManifest()).templates.single;
      expect(second.cacheKey, isNot(first.cacheKey));
      final p2 = await svc.ensureScript(second);
      expect(p2, isNot(p1));
      expect(File(p2).readAsStringSync().trim(), 'fps=30,fade=t=out');
      // The superseded revision is still on disk but is no longer reachable,
      // which is what makes publishing an update a no-bookkeeping operation.
      expect(File(p1).existsSync(), isTrue);
    });
  });

  group('policy rejection is distinct from a download failure', () {
    test('a GPL filter is REJECTED, not downloaded-and-run', () async {
      // eq exists in a GPL ffmpeg and not in the LGPL build we ship, so this
      // is both a policy failure and a guaranteed render failure.
      serveManifest([spec(graph: 'eq=contrast=1.4,fps=30')]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;
      await expectLater(
        svc.ensureScript(s),
        throwsA(isA<TemplatePluginRejectedError>()
            .having((e) => e.reason, 'reason', contains('eq'))),
      );
    });

    test('a file-reading filter is rejected', () async {
      serveManifest([spec(graph: 'movie=C\\:/Windows/win.ini,fps=30')]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;
      await expectLater(
          svc.ensureScript(s), throwsA(isA<TemplatePluginRejectedError>()));
    });

    test('a rejected script is not left on disk', () async {
      serveManifest([spec(graph: 'movie=C\\:/x.mp4,fps=30')]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;
      await expectLater(svc.ensureScript(s), throwsA(isA<Exception>()));
      final dir = Directory(TemplatePluginService.pluginDir);
      expect(
          dir.listSync().where((f) => f.path.endsWith('.ffscript')), isEmpty);
    });
  });

  group('render', () {
    test('produces a playable video and caches it', () async {
      if (ffmpegPath == null) return; // no ffmpeg: nothing to render
      serveManifest([spec()]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;

      final progress = <double>[];
      final path = await svc.render(s, onProgress: progress.add);
      expect(File(path).existsSync(), isTrue);
      expect(File(path).lengthSync(), greaterThan(1024));
      expect(progress.last, greaterThanOrEqualTo(0.9));

      final res = await VideoProcessingService.probeResolution(path);
      if (res != null) {
        expect(res.$1, 320);
        expect(res.$2, 180);
      }

      // Second render is free: the cached mp4 short-circuits.
      final after = requestCount;
      await svc.render(s);
      expect(requestCount, after, reason: 'rendered plugin must be cached');
    }, timeout: const Timeout(Duration(seconds: 180)));

    test('an allowed but broken graph is a RENDER error, and leaves no file',
        () async {
      if (ffmpegPath == null) return;
      // Passes the policy (every filter is allowed) but is not valid ffmpeg.
      serveManifest([spec(graph: 'geq=r=)))bogus')]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;
      await expectLater(
        svc.render(s),
        throwsA(isA<TemplatePluginRenderError>()),
      );
      final dir = Directory(TemplatePluginService.pluginDir);
      expect(dir.listSync().where((f) => f.path.endsWith('.mp4')), isEmpty,
          reason: 'a failed render must not leave a partial file to cache');
    }, timeout: const Timeout(Duration(seconds: 180)));
  });

  group('invalidate', () {
    test('clears the cached script and video', () async {
      if (ffmpegPath == null) return;
      serveManifest([spec()]);
      final svc = newService();
      final s = (await svc.loadManifest()).templates.single;
      await svc.render(s);
      expect(
          File('${TemplatePluginService.pluginDir}${Platform.pathSeparator}'
                  '${s.cacheKey}.mp4')
              .existsSync(),
          isTrue);
      svc.invalidate(s.cacheKey);
      expect(
          File('${TemplatePluginService.pluginDir}${Platform.pathSeparator}'
                  '${s.cacheKey}.mp4')
              .existsSync(),
          isFalse);
    }, timeout: const Timeout(Duration(seconds: 180)));
  });
}
