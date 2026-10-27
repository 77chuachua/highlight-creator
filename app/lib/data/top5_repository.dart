import 'dart:convert';
import 'dart:io';

import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/domain/entities/top5_entry.dart';

/// JSON-backed store for Top-5 reels.
///
/// A file beats a drift table here: the rows are a handful per month, nothing
/// joins to them, and a schema change in `database.dart` would force a
/// `build_runner` regeneration (the generated file has to be committed, so it
/// cannot be done silently). `top5.json` is edited by the app only.
class Top5Repository {
  Top5Repository({String? path})
      : _path = path ?? '${AppPaths.baseDir}${Platform.pathSeparator}top5.json';

  final String _path;

  String get path => _path;

  /// Every entry, newest reel first. A corrupt file yields an empty list rather
  /// than an exception: losing the picks must not block editing.
  List<Top5Entry> load() {
    try {
      final file = File(_path);
      if (!file.existsSync()) return const [];
      final raw = jsonDecode(file.readAsStringSync());
      final list =
          (raw is Map<String, Object?> ? raw['entries'] : raw) as List?;
      if (list == null) return const [];
      return [
        for (final item in list)
          if (item is Map<String, Object?>)
            Top5Entry.fromJson(item)
          else if (item is Map)
            Top5Entry.fromJson(Map<String, Object?>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// Write the whole list, replacing the file atomically-ish: a crash mid-write
  /// must not leave a half-written JSON that later reads as "no picks".
  void save(List<Top5Entry> entries) {
    final dir = File(_path).parent;
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final tmp = File('$_path.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'version': 1,
        'entries': [for (final e in entries) e.toJson()],
      }),
      flush: true,
    );
    if (File(_path).existsSync()) File(_path).deleteSync();
    tmp.renameSync(_path);
  }

  /// Entries of one reel bucket, ranked 1..N.
  List<Top5Entry> byBucket(Top5Level level, Top5Kind kind, String periodKey) {
    final rows = load()
        .where((e) =>
            e.level == level && e.kind == kind && e.periodKey == periodKey)
        .toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    return rows;
  }

  /// Replace one reel bucket with [entries]. Other buckets are
  /// left untouched.
  void replaceReel(
    Top5Level level,
    Top5Kind kind,
    String periodKey,
    List<Top5Entry> entries,
  ) {
    final rest = load()
        .where((e) =>
            !(e.level == level && e.kind == kind && e.periodKey == periodKey))
        .toList();
    save([...rest, ...entries]);
  }

  /// Candidates for a monthly reel: this month's weekly reels of [kind],
  /// ranked. A week key cannot be mapped to a month reliably, so the reel's
  /// own creation date decides which month it belongs to.
  List<Top5Entry> weeklyCandidates(Top5Kind kind, DateTime month) {
    final key = top5MonthKey(month);
    return load()
        .where((e) =>
            e.level == Top5Level.week &&
            e.kind == kind &&
            top5MonthKey(e.createdAt) == key)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Candidates for a yearly reel: the monthly reels that *belong* to this year.
  ///
  /// The monthly period key already carries its year (`2026-09`), so a December
  /// reel made in January still counts towards the previous year.
  List<Top5Entry> monthlyCandidates(Top5Kind kind, DateTime year) {
    final prefix = '${top5YearKey(year)}-';
    return load()
        .where((e) =>
            e.level == Top5Level.month &&
            e.kind == kind &&
            e.periodKey.startsWith(prefix))
        .toList()
      ..sort((a, b) => a.periodKey.compareTo(b.periodKey));
  }
}
