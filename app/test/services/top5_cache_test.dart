import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/top5_repository.dart';
import 'package:highlight_creator/domain/entities/top5_entry.dart';
import 'package:highlight_creator/services/top5_cache.dart';

void main() {
  final sep = Platform.pathSeparator;
  late Directory root;
  late Directory clips;
  late Top5Repository repo;

  setUp(() {
    root = Directory.systemTemp.createTempSync('top5_cache_');
    clips = Directory('${root.path}${sep}5best_clips')
      ..createSync(recursive: true);
    repo = Top5Repository(path: '${root.path}${sep}top5.json');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// The clip `_storeClip` writes for one rank (content is never inspected).
  String storeClip(Top5Level level, String period, Top5Kind kind, int rank) {
    final file = File('${clips.path}${sep}'
        '${Top5Cache.clipName(level, period, kind, rank)}');
    file.writeAsBytesSync(List<int>.filled(2048, 7));
    return file.path;
  }

  Top5Entry entry({
    Top5Level level = Top5Level.week,
    Top5Kind kind = Top5Kind.goal,
    String period = '2026-W43',
    int rank = 1,
    String title = '',
    String comment = '',
    String? clipPath,
    String sourceTimeslotId = '',
    String parentId = '',
  }) {
    return Top5Entry(
      id: '${level.name}_${period}_$rank',
      level: level,
      kind: kind,
      periodKey: period,
      rank: rank,
      clipPath: clipPath ?? storeClip(level, period, kind, rank),
      title: title,
      comment: comment,
      sourceTimeslotId: sourceTimeslotId,
      parentId: parentId,
      createdAt: DateTime(2026, 10, 21, 20),
    );
  }

  List<Top5CachedPick> picks({
    Top5Level level = Top5Level.week,
    Top5Kind kind = Top5Kind.goal,
    String period = '2026-W43',
    int wanted = 5,
  }) {
    return Top5Cache.picks(
      clipsDir: clips,
      repo: repo,
      level: level,
      kind: kind,
      periodKey: period,
      wanted: wanted,
    );
  }

  test('a folder without the reel restores nothing', () {
    expect(picks(), isEmpty);
    expect(
        picks(period: '2026-W44'), isEmpty,
        reason: 'a clip is only restored for its own period');
  });

  test('restores every rank with its title, comment and source slot', () {
    repo.replaceReel(Top5Level.week, Top5Kind.goal, '2026-W43', [
      for (var rank = 1; rank <= 5; rank++)
        entry(
          rank: rank,
          title: '第 $rank 球',
          comment: '旁白 $rank',
          sourceTimeslotId: 'slot-$rank',
        ),
    ]);

    final restored = picks();
    expect(restored.map((p) => p.rank), [1, 2, 3, 4, 5]);
    expect(restored.first.title, '第 1 球');
    expect(restored[3].comment, '旁白 4');
    expect(restored[4].sourceId, 'slot-5');
    expect(restored.every((p) => File(p.clipPath).existsSync()), isTrue);
  });

  test('a clip whose row is gone still restores, without copy', () {
    storeClip(Top5Level.week, '2026-W43', Top5Kind.goal, 2);

    final restored = picks();
    expect(restored, hasLength(1));
    expect(restored.single.rank, 2);
    expect(restored.single.title, isEmpty);
    expect(restored.single.comment, isEmpty);
    expect(restored.single.sourceId, isEmpty);
  });

  test('a row pointing at a clip elsewhere is trusted', () {
    final elsewhere = File('${root.path}${sep}kept_clip.mp4')
      ..writeAsBytesSync(List<int>.filled(2048, 1));
    repo.replaceReel(Top5Level.week, Top5Kind.goal, '2026-W43', [
      entry(rank: 3, clipPath: elsewhere.path, comment: '只有这一条'),
    ]);

    final restored = picks();
    expect(restored.single.rank, 3);
    expect(restored.single.clipPath, elsewhere.path);
    expect(restored.single.comment, '只有这一条');
  });

  test('a deleted clip leaves a hole, the other ranks stay', () {
    repo.replaceReel(Top5Level.week, Top5Kind.goal, '2026-W43', [
      for (var rank = 1; rank <= 5; rank++) entry(rank: rank),
    ]);
    File('${clips.path}${sep}'
            '${Top5Cache.clipName(Top5Level.week, '2026-W43', Top5Kind.goal, 3)}')
        .deleteSync();

    expect(picks().map((p) => p.rank), [1, 2, 4, 5]);
  });

  test('a monthly reel restores from the weekly entry it picked', () {
    repo.replaceReel(Top5Level.month, Top5Kind.goal, '2026-10', [
      entry(
        level: Top5Level.month,
        period: '2026-10',
        rank: 1,
        parentId: 'week_2026-W43_goal_1',
      ),
    ]);

    final restored = picks(level: Top5Level.month, period: '2026-10');
    expect(restored.single.sourceId, 'week_2026-W43_goal_1');
  });

  test('saves are a different reel from goals', () {
    storeClip(Top5Level.week, '2026-W43', Top5Kind.goal, 1);
    expect(picks(kind: Top5Kind.save), isEmpty);
  });

  test('a yearly reel restores ten ranks', () {
    repo.replaceReel(Top5Level.year, Top5Kind.goal, '2026', [
      for (var rank = 1; rank <= 10; rank++)
        entry(level: Top5Level.year, period: '2026', rank: rank),
    ]);

    expect(picks(level: Top5Level.year, period: '2026', wanted: 10),
        hasLength(10));
  });
}
