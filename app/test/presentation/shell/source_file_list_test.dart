import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/presentation/shell/source_file_list.dart';

/// Issues.md: the source list must show durations in h/m/s, not raw seconds.
void main() {
  group('formatHms', () {
    test('formats seconds/minutes/hours', () {
      expect(formatHms(0), '0s');
      expect(formatHms(12000), '12s');
      expect(formatHms(90 * 1000), '1m 30s');
      expect(formatHms(3600 * 1000), '1h');
      expect(formatHms(3600 * 1000 + 5 * 1000), '1h 5s');
      expect(formatHms(3600 * 1000 + 90 * 1000), '1h 1m 30s');
      expect(formatHms(7200 * 1000 + 45 * 60 * 1000 + 3 * 1000),
          '2h 45m 3s');
      expect(formatHms(7200 * 1000 + 45 * 1000 + 3 * 1000), '2h 48s');
    });

    test('rounds sub-second durations to the nearest second', () {
      expect(formatHms(1500), '2s');
      expect(formatHms(1400), '1s');
    });
  });
}