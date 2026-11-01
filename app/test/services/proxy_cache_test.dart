import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/services/phone_marking_server.dart';
import 'package:highlight_creator/services/proxy_cache.dart';

/// The two rules the phone's player depends on: the proxy file is named from
/// the source (never from a request), and Range math picks between 200, 206 and
/// 416. Both are pure functions, so they get checked here without a server, a
/// phone or an ffmpeg.
void main() {
  group('parseRange', () {
    const total = 1000;

    test('an absent header means the whole file', () {
      expect(PhoneMarkingServer.parseRange(null, total), isNull);
    });

    test('an open-ended range ends at the last byte', () {
      final range = PhoneMarkingServer.parseRange('bytes=500-', total)!;
      expect(range.start, 500);
      expect(range.end, 999);
      expect(range.satisfiable, isTrue);
    });

    test('an end past EOF is clamped instead of rejected', () {
      final range = PhoneMarkingServer.parseRange('bytes=0-99999', total)!;
      expect(range.start, 0);
      expect(range.end, 999);
    });

    test('a suffix range asks for the tail', () {
      final range = PhoneMarkingServer.parseRange('bytes=-200', total)!;
      expect(range.start, 800);
      expect(range.end, 999);
    });

    test('a start past EOF is unsatisfiable, i.e. 416', () {
      final range = PhoneMarkingServer.parseRange('bytes=1000-', total)!;
      expect(range.satisfiable, isFalse);
    });

    test('garbage, inverted and multi-range fall back to the whole file', () {
      expect(PhoneMarkingServer.parseRange('bytes=0-1,5-6', total), isNull);
      expect(PhoneMarkingServer.parseRange('items=0-1', total), isNull);
      expect(PhoneMarkingServer.parseRange('bytes=9-2', total), isNull);
      expect(PhoneMarkingServer.parseRange('bytes=-', total), isNull);
    });
  });

  group('proxy paths', () {
    test('a source path maps to one sha1 name under temp\\proxy', () {
      final a = ProxyCache.pathFor(r'C:\footage\a.mp4');
      expect(a, ProxyCache.pathFor(r'C:\footage\a.mp4'));
      expect(a, isNot(ProxyCache.pathFor(r'C:\footage\b.mp4')));
      expect(a, startsWith(ProxyCache.dir));
      expect(a, endsWith('.mp4'));
      // 40 hex characters plus ".mp4".
      expect(a.split(RegExp(r'[\\/]')).last.length, 44);
    });

    test('the sidecar sits beside its mp4', () {
      final proxy = ProxyCache.pathFor(r'C:\footage\a.mp4');
      expect(
        ProxyCache.sidecarFor(proxy),
        '${proxy.substring(0, proxy.length - 4)}.json',
      );
    });
  });

  group('ProxyEntry sidecar', () {
    test('round-trips every documented field', () {
      final entry = ProxyEntry(
        sourcePath: r'C:\footage\a.mp4',
        proxyPath: r'C:\temp\proxy\abc.mp4',
        state: ProxyState.working,
        progress: 42,
        sizeBytes: 0,
        updatedAt: DateTime.parse('2026-10-28T12:00:00.000'),
      );
      final back = ProxyEntry.fromJson(jsonDecode(jsonEncode(entry.toJson())))!;
      expect(back.sourcePath, entry.sourcePath);
      expect(back.proxyPath, entry.proxyPath);
      expect(back.state, ProxyState.working);
      expect(back.progress, 42);
      expect(back.error, isNull);
      expect(back.updatedAt, entry.updatedAt);
    });

    test('rejects a sidecar with an unknown state', () {
      expect(
        ProxyEntry.fromJson(
          {'sourcePath': 'a', 'proxyPath': 'b', 'state': 'nope'},
        ),
        isNull,
      );
    });
  });
}
