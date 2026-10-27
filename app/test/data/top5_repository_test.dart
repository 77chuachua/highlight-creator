import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/top5_repository.dart';
import 'package:highlight_creator/domain/entities/top5_entry.dart';

void main() {
  late Directory dir;
  late Top5Repository repo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('top5_repo_');
    repo = Top5Repository(path: '${dir.path}\\top5.json');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Top5Entry entry({
    Top5Level level = Top5Level.week,
    Top5Kind kind = Top5Kind.goal,
    String period = '2026-W42',
    int rank = 1,
    String title = '第 12 分钟 · 禁区外远射',
    String comment = '',
    DateTime? createdAt,
  }) {
    return Top5Entry(
      id: '${level.name}_${period}_$rank',
      level: level,
      kind: kind,
      periodKey: period,
      rank: rank,
      clipPath: '${dir.path}\\clip_$rank.mp4',
      title: title,
      comment: comment,
      createdAt: createdAt ?? DateTime(2026, 10, 14, 20),
    );
  }

  List<Top5Entry> reelOfFive({int from = 1}) => [
        for (var i = from; i < from + 5; i++) entry(rank: i, comment: '旁白 $i'),
      ];

  group('period keys', () {
    test('a date maps to an ISO week, a month and a year', () {
      final date = DateTime(2026, 10, 14);
      expect(top5WeekKey(date), '2026-W42');
      expect(top5MonthKey(date), '2026-10');
      expect(top5YearKey(date), '2026');
      expect(top5PeriodKey(Top5Level.week, date), '2026-W42');
      expect(top5PeriodKey(Top5Level.month, date), '2026-10');
      expect(top5PeriodKey(Top5Level.year, date), '2026');
    });

    test('the project date decides the week, not today', () {
      // The weekly reel is anchored on the project, not the clock: a project
      // from Oct 21 stays in week 43 even when it is reopened on Oct 26, which
      // the calendar already calls week 44.
      expect(top5WeekKey(DateTime(2026, 10, 21)), '2026-W43');
      expect(top5WeekKey(DateTime(2026, 10, 23)), '2026-W43');
      expect(top5WeekKey(DateTime(2026, 10, 26)), '2026-W44');
      // One month, two weeks: the monthly reel still lines up with October.
      expect(top5MonthKey(DateTime(2026, 10, 21)), '2026-10');
      expect(top5MonthKey(DateTime(2026, 10, 26)), '2026-10');
    });
  });

  group('round trip', () {
    test('keeps rank, title and the comment meant for narration', () {
      final reel = reelOfFive();
      repo.replaceReel(Top5Level.week, Top5Kind.goal, '2026-W42', reel);

      final loaded = repo.byBucket(Top5Level.week, Top5Kind.goal, '2026-W42');
      expect(loaded, hasLength(5));
      expect(loaded.map((e) => e.rank), [1, 2, 3, 4, 5]);
      expect(loaded.first.title, '第 12 分钟 · 禁区外远射');
      expect(loaded[3].comment, '旁白 4');
    });

    test('a corrupt file reads as no picks instead of throwing', () {
      File('${dir.path}\\top5.json').writeAsStringSync('{not json');
      expect(repo.load(), isEmpty);
    });
  });

  group('replaceReel', () {
    test('replaces one bucket and leaves the others alone', () {
      repo.replaceReel(Top5Level.week, Top5Kind.goal, '2026-W42', reelOfFive());
      repo.replaceReel(Top5Level.week, Top5Kind.save, '2026-W42', [
        entry(kind: Top5Kind.save, rank: 1, title: '门将封堵'),
      ]);

      repo.replaceReel(Top5Level.week, Top5Kind.goal, '2026-W42', [
        entry(rank: 1, title: '新的第一'),
      ]);

      final goals = repo.byBucket(Top5Level.week, Top5Kind.goal, '2026-W42');
      final saves = repo.byBucket(Top5Level.week, Top5Kind.save, '2026-W42');
      expect(goals, hasLength(1));
      expect(goals.single.title, '新的第一');
      expect(saves, hasLength(1), reason: 'the save reel must survive');
      expect(saves.single.title, '门将封堵');
    });
  });

  group('candidates', () {
    test('monthly reel picks this month\'s weekly reels of the same kind', () {
      repo.replaceReel(Top5Level.week, Top5Kind.goal, '2026-W41', [
        entry(period: '2026-W41', rank: 1, createdAt: DateTime(2026, 10, 7)),
      ]);
      repo.replaceReel(Top5Level.week, Top5Kind.goal, '2026-W42', [
        entry(period: '2026-W42', rank: 1, createdAt: DateTime(2026, 10, 14)),
      ]);
      repo.replaceReel(Top5Level.week, Top5Kind.goal, '2026-W35', [
        entry(period: '2026-W35', rank: 1, createdAt: DateTime(2026, 8, 26)),
      ]);
      repo.replaceReel(Top5Level.week, Top5Kind.save, '2026-W42', [
        entry(kind: Top5Kind.save, rank: 1, createdAt: DateTime(2026, 10, 14)),
      ]);

      final october =
          repo.weeklyCandidates(Top5Kind.goal, DateTime(2026, 10, 14));
      expect(october.map((e) => e.periodKey), ['2026-W41', '2026-W42'],
          reason: 'August belongs to another month, saves to another kind');
    });

    test('yearly reel picks this year\'s monthly reels', () {
      repo.replaceReel(Top5Level.month, Top5Kind.goal, '2026-09', [
        entry(
            level: Top5Level.month,
            period: '2026-09',
            rank: 1,
            createdAt: DateTime(2026, 10, 1)),
      ]);
      repo.replaceReel(Top5Level.month, Top5Kind.goal, '2025-12', [
        entry(
            level: Top5Level.month,
            period: '2025-12',
            rank: 1,
            createdAt: DateTime(2026, 1, 2)),
      ]);

      final thisYear =
          repo.monthlyCandidates(Top5Kind.goal, DateTime(2026, 6, 1));
      expect(thisYear.map((e) => e.periodKey), ['2026-09'],
          reason: 'the 2025 reel was created in 2026 but is not a 2026 reel');
    });
  });
}
