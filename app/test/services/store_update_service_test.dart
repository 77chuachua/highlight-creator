import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/services/store_update_service.dart';

/// The Dart half of the Store update check. Two things must hold: only a clear
/// "available" may prompt, and a channel that is missing (a non-Windows build, or
/// a runner predating the channel) must read as "unavailable" instead of throwing
/// on startup.
void main() {
  // TestDefaultBinaryMessengerBinding needs the binding up before any mock
  // handler is installed.
  TestWidgetsFlutterBinding.ensureInitialized();

  final channel = StoreUpdateService.channel;

  void replyWith(Object? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => handler(call));
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('parse', () {
    test('an available update carries its version', () {
      final info = StoreUpdateService.parse(<Object?, Object?>{
        'state': 'available',
        'version': '0.4.0.0',
        'detail': '',
      });
      expect(info.isAvailable, isTrue);
      expect(info.version, '0.4.0.0');
      expect(info.detail, isNull, reason: 'empty strings read as absent');
    });

    test('a current package does not prompt', () {
      expect(StoreUpdateService.parse(<Object?, Object?>{'state': 'current'})
          .isAvailable, isFalse);
    });

    test('a pending answer is reported as pending, not as up to date', () {
      expect(StoreUpdateService.parse(<Object?, Object?>{'state': 'pending'})
          .isPending, isTrue);
    });

    test('a malformed reply is unavailable', () {
      expect(StoreUpdateService.parse(null).state, 'unavailable');
      expect(StoreUpdateService.parse('nope').state, 'unavailable');
      expect(StoreUpdateService.parse(<Object?, Object?>{'state': 42}).state,
          'unavailable');
      expect(StoreUpdateService.parse(<Object?, Object?>{'state': ''}).state,
          'unavailable');
    });

    test('an unavailable reply keeps the reason for the log', () {
      final info = StoreUpdateService.parse(<Object?, Object?>{
        'state': 'unavailable',
        'detail': '0x80073D02 package is not installed by the Store',
      });
      expect(info.isAvailable, isFalse);
      expect(info.detail, contains('0x80073D02'));
    });
  });

  group('channel', () {
    test('a reply from the runner is parsed', () async {
      replyWith((call) {
        expect(call.method, 'check');
        return <Object?, Object?>{'state': 'available', 'version': '1.2.3.4'};
      });
      final info = await StoreUpdateService.check();
      expect(info.isAvailable, isTrue);
      expect(info.version, '1.2.3.4');
    });

    test('a missing channel is unavailable, not an exception', () async {
      final info = await StoreUpdateService.check();
      expect(info.state, 'unavailable');
      expect(info.isAvailable, isFalse);
    });

    test('a platform error is unavailable', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'boom', message: 'store exploded');
      });
      final info = await StoreUpdateService.check();
      expect(info.state, 'unavailable');
      expect(info.detail, 'store exploded');
    });
  });

  group('checkWhenReady', () {
    test('polls until the runner answers', () async {
      var calls = 0;
      final info = await StoreUpdateService.checkWhenReady(
        attempts: 5,
        interval: Duration.zero,
        probe: () async {
          calls++;
          return calls < 3
              ? const StoreUpdateInfo('pending')
              : const StoreUpdateInfo('available', version: '1.2.3.4');
        },
      );
      expect(info.isAvailable, isTrue);
      expect(calls, 3, reason: 'stops as soon as the answer is not pending');
    });

    test('gives up after the attempt budget instead of hanging', () async {
      var calls = 0;
      final info = await StoreUpdateService.checkWhenReady(
        attempts: 3,
        interval: Duration.zero,
        probe: () async {
          calls++;
          return const StoreUpdateInfo('pending');
        },
      );
      expect(calls, 3);
      expect(info.isAvailable, isFalse);
    });
  });
}
