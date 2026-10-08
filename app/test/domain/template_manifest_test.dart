import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/domain/entities/template_manifest.dart';

/// The manifest is authored by someone else and parsed on every launch, so
/// every rejection path matters: a malformed catalogue must produce a precise
/// message naming the offending template, never a stack trace or a silent skip.
void main() {
  Map<String, dynamic> entry({
    String id = 'neon-grid',
    String type = 'startup',
    String url = 'https://example.test/neon.ffscript',
    String? sha256,
    int sizeBytes = 128,
    String? revision = 'r1',
    Map<String, dynamic>? render,
  }) =>
      {
        'id': id,
        'name': 'Neon Grid',
        'description': 'test template',
        'author': 'someone',
        'type': type,
        'script': {
          'url': url,
          if (sha256 != null) 'sha256': sha256,
          'sizeBytes': sizeBytes,
          if (revision != null) 'revision': revision,
        },
        'render': render ?? {'durationSecs': 2.0, 'width': 640, 'height': 360},
      };

  TemplateManifest parse(List<Map<String, dynamic>> templates) =>
      TemplateManifest.fromJson({
        'schemaVersion': 1,
        'updatedAt': '2026-10-04',
        'templates': templates,
      });

  group('valid manifests', () {
    test('parses a complete entry', () {
      final m = parse([entry()]);
      expect(m.templates, hasLength(1));
      final t = m.templates.single;
      expect(t.id, 'neon-grid');
      expect(t.type, TemplateType.startup);
      expect(t.author, 'someone');
      expect(t.script.sha256, isNull);
      expect(t.render.durationSecs, 2.0);
      expect(t.render.withBgm, isFalse);
    });

    test('accepts a hash and lowercases it', () {
      final m = parse([entry(sha256: 'A' * 64)]);
      expect(m.templates.single.script.sha256, 'a' * 64);
    });

    test('revision falls back to the hash prefix, then to 1', () {
      expect(
          parse([entry(sha256: 'b' * 64, revision: null)])
              .templates
              .single
              .script
              .revision,
          'b' * 12);
      expect(parse([entry(revision: null)]).templates.single.script.revision, '1');
    });

    test('unknown fields are ignored, so authors can add metadata', () {
      final e = entry()..['homepage'] = 'https://example.test';
      expect(parse([e]).templates, hasLength(1));
    });

    test('defaults render to 720p when omitted', () {
      final e = entry()..['render'] = <String, dynamic>{};
      final r = parse([e]).templates.single.render;
      expect(r.width, 1280);
      expect(r.height, 720);
      expect(r.durationSecs, 4.0);
    });
  });

  group('rejected manifests', () {
    void expectRejected(List<Map<String, dynamic>> templates, Matcher message) {
      expect(
        () => parse(templates),
        throwsA(isA<TemplateManifestFormatException>()
            .having((e) => e.reason, 'reason', message)),
      );
    }

    test('unsupported type, including backgroundMusic', () {
      expectRejected([entry(type: 'backgroundMusic')], contains('type'));
      expectRejected([entry(type: 'sticker')], contains('type'));
    });

    test('missing required field names the field', () {
      final e = entry()..remove('name');
      expectRejected([e], contains('name'));
      final s = entry();
      (s['script'] as Map<String, dynamic>).remove('url');
      expectRejected([s], contains('url'));
    });

    test('duplicate ids, which would collide in the on-disk cache', () {
      expectRejected([entry(), entry()], contains('duplicate'));
    });

    test('a non-http url, so a manifest cannot read a local path', () {
      expectRejected([entry(url: 'file:///C:/Windows/win.ini')],
          contains('http://'));
      expectRejected([entry(url: 'data:text/plain;base64,AAAA')],
          contains('http://'));
    });

    test('a malformed hash', () {
      expectRejected([entry(sha256: 'nothex')], contains('sha256'));
      expectRejected([entry(sha256: 'a' * 63)], contains('sha256'));
    });

    test('an implausible script size', () {
      expectRejected([entry(sizeBytes: 0)], contains('sizeBytes'));
      expectRejected([entry(sizeBytes: 99999999)], contains('sizeBytes'));
    });

    test('an out-of-range duration', () {
      expectRejected([entry(render: {'durationSecs': 0.0})],
          contains('durationSecs'));
      expectRejected([entry(render: {'durationSecs': 600.0})],
          contains('durationSecs'));
    });

    test('odd dimensions, which yuv420p cannot encode', () {
      expectRejected([entry(render: {'width': 641, 'height': 360})],
          contains('width/height'));
    });

    test('an id that is not filename-safe', () {
      expectRejected([entry(id: '../escape')], contains('filename-safe'));
      expectRejected([entry(id: 'a/b')], contains('filename-safe'));
    });

    test('a schema this build is too old to read', () {
      expect(
        () => TemplateManifest.fromJson({
          'schemaVersion': kTemplateManifestSchema + 1,
          'templates': [entry()],
        }),
        throwsA(isA<TemplateManifestFormatException>()
            .having((e) => e.reason, 'reason', contains('newer'))),
      );
    });

    test('a document that is not a template manifest at all', () {
      expect(
        () => TemplateManifest.fromJson(jsonDecode('{"hello":"world"}')),
        throwsA(isA<TemplateManifestFormatException>()),
      );
      expect(
        () => TemplateManifest.fromJson({'templates': 'nope'}),
        throwsA(isA<TemplateManifestFormatException>()),
      );
    });
  });

  group('cacheKey', () {
    test('embeds the revision so publishing an update invalidates the cache',
        () {
      final a = parse([entry(revision: 'r1')]).templates.single;
      final b = parse([entry(revision: 'r2')]).templates.single;
      expect(a.cacheKey, isNot(b.cacheKey));
      expect(a.cacheKey, contains('neon-grid'));
    });

    test('is stable for a given id and revision', () {
      final a = parse([entry(revision: 'r1')]).templates.single;
      final b = parse([entry(revision: 'r1')]).templates.single;
      expect(a.cacheKey, b.cacheKey);
    });
  });
}
