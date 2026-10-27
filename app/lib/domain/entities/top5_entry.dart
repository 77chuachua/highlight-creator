import 'dart:io';

/// Where a Top-5 reel sits in the weekly → monthly → yearly pyramid.
enum Top5Level { week, month, year }

/// What a Top-5 reel collects. Goals and saves are picked separately: a save
/// is a different story and deserves its own reel.
enum Top5Kind { goal, save }

/// One slot of a Top-5 reel: the media plus the copy that ships with it.
///
/// The clip lives in its own file under `%USERPROFILE%\HighlightCreator\5best\`
/// because a project's sources move (and a weekly reel must survive the source
/// being deleted). A monthly/yearly entry re-uses the clip it picked rather
/// than reaching back to a project that may be long gone.
class Top5Entry {
  final String id;
  final Top5Level level;
  final Top5Kind kind;

  /// `2026-W42`, `2026-10` or `2026` — one bucket per reel.
  final String periodKey;

  /// 1 (best) upward: weekly and monthly reels stack 5, yearly reels 10.
  final int rank;

  final String clipPath;

  /// Shown on the rank card; defaults to the timeslot's description.
  final String title;

  /// Narration copy. Stored only for now — the TTS voice-over will read it.
  final String comment;

  /// The narration audio for this slot: the user's own recording when there
  /// is one, otherwise the synthesised file. Empty when the clip has no
  /// narration at all.
  final String narrationPath;

  /// Weekly entries come from a timeslot; monthly/yearly pick another entry.
  final String sourceTimeslotId;
  final String parentId;

  final DateTime createdAt;

  const Top5Entry({
    required this.id,
    required this.level,
    required this.kind,
    required this.periodKey,
    required this.rank,
    required this.clipPath,
    this.title = '',
    this.comment = '',
    this.narrationPath = '',
    this.sourceTimeslotId = '',
    this.parentId = '',
    required this.createdAt,
  });

  Top5Entry copyWith({
    int? rank,
    String? clipPath,
    String? title,
    String? comment,
    String? narrationPath,
  }) {
    return Top5Entry(
      id: id,
      level: level,
      kind: kind,
      periodKey: periodKey,
      rank: rank ?? this.rank,
      clipPath: clipPath ?? this.clipPath,
      title: title ?? this.title,
      comment: comment ?? this.comment,
      narrationPath: narrationPath ?? this.narrationPath,
      sourceTimeslotId: sourceTimeslotId,
      parentId: parentId,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'level': level.name,
        'kind': kind.name,
        'periodKey': periodKey,
        'rank': rank,
        'clipPath': clipPath,
        'title': title,
        'comment': comment,
        'narrationPath': narrationPath,
        'sourceTimeslotId': sourceTimeslotId,
        'parentId': parentId,
        'createdAt': createdAt.toIso8601String(),
      };

  /// Tolerant parse: a hand-edited or older `top5.json` must not brick the
  /// feature, so unknown levels/kinds fall back instead of throwing.
  factory Top5Entry.fromJson(Map<String, Object?> json) {
    T byName<T extends Enum>(List<T> values, Object? raw, T fallback) {
      for (final v in values) {
        if (v.name == raw) return v;
      }
      return fallback;
    }

    return Top5Entry(
      id: (json['id'] as String?) ?? '',
      level: byName(Top5Level.values, json['level'], Top5Level.week),
      kind: byName(Top5Kind.values, json['kind'], Top5Kind.goal),
      periodKey: (json['periodKey'] as String?) ?? '',
      rank: (json['rank'] as num?)?.toInt() ?? 1,
      clipPath: (json['clipPath'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      comment: (json['comment'] as String?) ?? '',
      narrationPath: (json['narrationPath'] as String?) ?? '',
      sourceTimeslotId: (json['sourceTimeslotId'] as String?) ?? '',
      parentId: (json['parentId'] as String?) ?? '',
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.now(),
    );
  }

  /// True when the file backing this slot still exists.
  bool get clipExists => clipPath.isNotEmpty && File(clipPath).existsSync();
}

/// `2026-W42` for [date]. Weeks are only used as a bucket label, so the
/// ISO year-boundary case (week 52/53 spilling into January) is accepted.
String top5WeekKey(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final dayOfYear = day.difference(DateTime(day.year, 1, 1)).inDays + 1;
  final week = ((dayOfYear - day.weekday + 10) / 7).floor().clamp(1, 53);
  return '${day.year}-W${week.toString().padLeft(2, '0')}';
}

/// `2026-10` for [date].
String top5MonthKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}';

/// `2026` for [date].
String top5YearKey(DateTime date) => '${date.year}';

/// The bucket key for [level] at [date].
String top5PeriodKey(Top5Level level, DateTime date) => switch (level) {
      Top5Level.week => top5WeekKey(date),
      Top5Level.month => top5MonthKey(date),
      Top5Level.year => top5YearKey(date),
    };
