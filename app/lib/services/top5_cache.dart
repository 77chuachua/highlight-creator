import 'dart:io';

import 'package:highlight_creator/data/top5_repository.dart';
import 'package:highlight_creator/domain/entities/top5_entry.dart';

/// One slot of a reel that is already on disk.
class Top5CachedPick {
  /// 1 (best) upward: the slot's place in the reel.
  final int rank;

  final String clipPath;

  /// The title the slot was picked with; empty when only the clip is left.
  final String title;

  /// The narration copy that was typed in for this slot.
  final String comment;

  /// Where the slot was picked from: the timeslot id of a weekly reel, the
  /// entry id of a monthly/yearly one. Empty when `top5.json` forgot the row.
  final String sourceId;

  const Top5CachedPick({
    required this.rank,
    required this.clipPath,
    this.title = '',
    this.comment = '',
    this.sourceId = '',
  });
}

/// Reads back the reel already rendered for a period.
///
/// The reel's own clips in `5best_clips` are the deliverable and outlive both
/// the dialog and `top5.json`, so reopening the dialog fills the ranking from
/// them instead of asking for the same picks again. The comment never lives in
/// a file name, so titles and comments come from `top5.json`; a clip whose row
/// is gone still restores (its rank, with a fallback title).
class Top5Cache {
  const Top5Cache._();

  /// The file name one rank of a reel owns; `_storeClip()` writes exactly this.
  static String clipName(
          Top5Level level, String periodKey, Top5Kind kind, int rank) =>
      '${level.name}_${periodKey}_${kind.name}_$rank.mp4';

  /// The reel's slots for [periodKey], best rank first. Ranks whose clip is
  /// gone are skipped, so a half-cleaned folder restores what it still has.
  static List<Top5CachedPick> picks({
    required Directory clipsDir,
    required Top5Repository repo,
    required Top5Level level,
    required Top5Kind kind,
    required String periodKey,
    required int wanted,
  }) {
    if (!clipsDir.existsSync()) return const [];
    Map<int, Top5Entry> entries;
    try {
      entries = {
        for (final e in repo.byBucket(level, kind, periodKey)) e.rank: e,
      };
    } catch (_) {
      // An unreadable top5.json costs the titles, not the picks.
      entries = const {};
    }
    final picks = <Top5CachedPick>[];
    for (var rank = 1; rank <= wanted; rank++) {
      final entry = entries[rank];
      final canonical = '${clipsDir.path}${Platform.pathSeparator}'
          '${clipName(level, periodKey, kind, rank)}';
      // The row names the file that was actually written; the canonical name
      // covers a clip whose row was lost. Without either there is nothing to
      // restore for this rank.
      final String clipPath;
      if (entry != null && entry.clipExists) {
        clipPath = entry.clipPath;
      } else if (File(canonical).existsSync()) {
        clipPath = canonical;
      } else {
        continue;
      }
      final sourceId = entry == null
          ? ''
          : (entry.sourceTimeslotId.isNotEmpty
              ? entry.sourceTimeslotId
              : entry.parentId);
      picks.add(Top5CachedPick(
        rank: rank,
        clipPath: clipPath,
        title: entry?.title.trim() ?? '',
        comment: entry?.comment ?? '',
        sourceId: sourceId,
      ));
    }
    return picks;
  }
}
