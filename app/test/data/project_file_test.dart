import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/project_file.dart';

/// A Top-5 reel's week comes from the project date. Getting this wrong moves
/// a reel a week ahead, which is exactly the bug this file guards.
void main() {
  group('projectDateFromFileName', () {
    test('reads the date autosave puts in the name', () {
      expect(projectDateFromFileName('2026-10-21.hlcproj'),
          DateTime(2026, 10, 21));
      expect(
        projectDateFromFileName(r'C:\Users\me\HighlightCreator\results\2026-10-21.hlcproj'),
        DateTime(2026, 10, 21),
      );
    });

    test('accepts a trailing label and single-digit parts', () {
      expect(projectDateFromFileName('2026-10-21 比赛.hlcproj'),
          DateTime(2026, 10, 21));
      expect(projectDateFromFileName('备份-2026-1-5.hlcproj'),
          DateTime(2026, 1, 5));
    });

    test('returns null when the name carries no date', () {
      expect(projectDateFromFileName('New Project.hlcproj'), isNull);
      expect(projectDateFromFileName('final.hlcproj'), isNull);
      expect(projectDateFromFileName(''), isNull);
    });

    test('rejects impossible dates instead of rolling them over', () {
      // DateTime(2026, 13, 45) would silently become 2027-02-14.
      expect(projectDateFromFileName('2026-13-45.hlcproj'), isNull);
      expect(projectDateFromFileName('2026-02-30.hlcproj'), isNull);
      expect(projectDateFromFileName('2026-00-10.hlcproj'), isNull);
    });
  });

  group('projectDateOf', () {
    test('prefers the date written inside the file', () {
      final date = projectDateOf(
        {'date': '2026-10-21'},
        r'C:\results\2026-10-26.hlcproj',
      );
      expect(date, DateTime(2026, 10, 21));
    });

    test('falls back to the file name for older projects', () {
      expect(
        projectDateOf({}, r'C:\results\2026-10-21.hlcproj'),
        DateTime(2026, 10, 21),
      );
    });

    test('ignores a broken date and uses the name', () {
      expect(
        projectDateOf({'date': 'not a date'}, '2026-10-21.hlcproj'),
        DateTime(2026, 10, 21),
      );
    });

    test('returns null when neither source has one', () {
      expect(projectDateOf({}, null), isNull);
      expect(projectDateOf({}, 'New Project.hlcproj'), isNull);
    });
  });

  group('projectDateValue', () {
    test('writes zero-padded yyyy-mm-dd', () {
      expect(projectDateValue(DateTime(2026, 10, 21)), '2026-10-21');
      expect(projectDateValue(DateTime(2026, 1, 5)), '2026-01-05');
    });

    test('round-trips through the file name parser', () {
      final date = DateTime(2026, 10, 21);
      expect(projectDateFromFileName('${projectDateValue(date)}.hlcproj'), date);
    });
  });
}
