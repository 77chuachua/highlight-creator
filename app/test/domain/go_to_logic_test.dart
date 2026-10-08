import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/presentation/shell/go_to_dialog.dart';

/// Pure logic behind the Go-to dialog: hh:mm:ss parsing and combined-source
/// seek mapping (no widget/ffmpeg dependency).
void main() {
  group('parseHms', () {
    test('full hh:mm:ss', () {
      expect(parseHms('21:00:00'), const Duration(hours: 21));
      expect(parseHms('00:10:00'), const Duration(minutes: 10));
    });
    test('mm:ss is padded to hh:mm:ss', () {
      expect(parseHms('10:00'), const Duration(minutes: 10));
      expect(parseHms('01:30'), const Duration(minutes: 1, seconds: 30));
    });
    test('malformed input returns null', () {
      expect(parseHms(''), isNull);
      expect(parseHms('abc'), isNull);
      expect(parseHms('1:2:3:4'), isNull);
      expect(parseHms('-1:00:00'), isNull);
      expect(parseHms('00:61:00'), isNull); // minutes > 59
      expect(parseHms('00:00:61'), isNull); // seconds > 59
    });
  });

  group('parseHmsParts (three separate hh/mm/ss inputs)', () {
    test('full h:m:s', () {
      expect(parseHmsParts('21', '00', '00'), const Duration(hours: 21));
      expect(parseHmsParts('00', '10', '00'), const Duration(minutes: 10));
      expect(parseHmsParts('00', '01', '30'),
          const Duration(minutes: 1, seconds: 30));
    });
    test('empty fields count as zero', () {
      expect(parseHmsParts('', '30', ''), const Duration(minutes: 30));
      expect(parseHmsParts('', '', '5'), const Duration(seconds: 5));
    });
    test('malformed input returns null', () {
      expect(parseHmsParts('abc', '00', '00'), isNull);
      expect(parseHmsParts('-1', '00', '00'), isNull);
      expect(parseHmsParts('00', '61', '00'), isNull); // minutes > 59
      expect(parseHmsParts('00', '00', '61'), isNull); // seconds > 59
    });
  });

  group('resolveGlobalSeek', () {
    const dur = [10000, 20000, 50000]; // 3 combined sources
    test('offset inside the first source', () {
      expect(resolveGlobalSeek(dur, 5000), (0, 5000));
    });
    test('offset inside a later source is shifted by cumulative durations',
        () {
      expect(resolveGlobalSeek(dur, 15000), (1, 5000));
      expect(resolveGlobalSeek(dur, 30000), (2, 0));
    });
    test('offset past the total clamps to the last source', () {
      expect(resolveGlobalSeek(dur, 100000), (2, 50000));
    });
    test('negative offset clamps to zero', () {
      expect(resolveGlobalSeek(dur, -5), (0, 0));
    });
    test('empty duration list is safe', () {
      expect(resolveGlobalSeek(const [], 10), (0, 0));
    });
  });
}