/// Batch bookkeeping for 「AI 打点」: many match videos in, one `.hlcproj` out.
///
/// The dialog runs the same per-file pipeline for one file at a time —
/// audio → motion → candidates → per-segment VLM judgement — strictly serially
/// (docs/ai_marking.md §批量). Everything that decides *order*, *grouping*,
/// *totals* and the *multi-source project file* lives here as pure Dart, so
/// `temp/ai_batch_probe.dart` can exercise it without a screen, ffmpeg or a
/// model.
///
/// What is **not** here: any change to detection or to the model's bar. The
/// candidate count per file is still `mergeCandidateChannels`' 60-cap union and
/// the verdict is still the model's `highlight` flag.
library;

import 'package:highlight_creator/services/ai_marking_service.dart';

/// The last path segment, `X.MP4` from `D:\DCIM\X.MP4`.
String fileNameOf(String path) => path.split(RegExp(r'[\\/]')).last;

/// The batch order: by **file name**, numeric runs compared as numbers and
/// letters case-insensitively, so `GX0111.MP4` sorts before `GX0112.MP4` and
/// `part9` before `part10` (a plain string compare would put `part10` first).
/// Duplicate paths are dropped; ties fall back to the full path so the order is
/// deterministic.
List<String> sortBatchFiles(Iterable<String> paths) {
  final unique = <String>{};
  for (final path in paths) {
    final trimmed = path.trim();
    if (trimmed.isNotEmpty) unique.add(trimmed);
  }
  final sorted = unique.toList()
    ..sort((a, b) {
      final byName = _compareNames(fileNameOf(a), fileNameOf(b));
      return byName != 0 ? byName : a.compareTo(b);
    });
  return sorted;
}

/// Natural, case-insensitive comparison of two file names: digit runs compare
/// by value (and by length, so leading zeros do not matter), everything else by
/// code unit.
int _compareNames(String a, String b) {
  final left = a.toLowerCase();
  final right = b.toLowerCase();
  var i = 0;
  var j = 0;
  while (i < left.length && j < right.length) {
    final l = left.codeUnitAt(i);
    final r = right.codeUnitAt(j);
    final lDigit = _isDigit(l);
    final rDigit = _isDigit(r);
    if (lDigit && rDigit) {
      final leftStart = i;
      final rightStart = j;
      while (i < left.length && _isDigit(left.codeUnitAt(i))) {
        i++;
      }
      while (j < right.length && _isDigit(right.codeUnitAt(j))) {
        j++;
      }
      final leftRun = left.substring(leftStart, i).replaceFirst(
            RegExp(r'^0+(?=\d)'),
            '',
          );
      final rightRun = right.substring(rightStart, j).replaceFirst(
            RegExp(r'^0+(?=\d)'),
            '',
          );
      if (leftRun.length != rightRun.length) {
        return leftRun.length - rightRun.length;
      }
      final byValue = leftRun.compareTo(rightRun);
      if (byValue != 0) return byValue;
      continue;
    }
    if (l != r) return l - r;
    i++;
    j++;
  }
  return (left.length - i) - (right.length - j);
}

bool _isDigit(int codeUnit) => codeUnit >= 0x30 && codeUnit <= 0x39;

/// One selected file and everything the pipeline found in it.
///
/// Mutable on purpose: the dialog creates one per selected file up front, then
/// fills `segments` once detection is done and lets each `AiSegment.verdict`
/// land as the model answers, which is what the live candidate list renders.
class AiFileResult {
  AiFileResult({required this.path});

  final String path;

  /// Filled from the picker's ffprobe (or the start line's probe); 0 when the
  /// file could not be read, which the writer passes through as 0.
  int durationMs = 0;

  int width = 0;
  int height = 0;

  /// Candidates in timeline order — never clipped here, the 60-cap is
  /// `mergeCandidateChannels`' job.
  List<AiSegment> segments = <AiSegment>[];

  /// True when this file failed as a whole (ffmpeg refused it, the WAV could
  /// not be parsed, …): the batch records it and moves to the next file.
  bool skipped = false;

  /// Why it was skipped, for `[ai-marking] file i/n skipped ...`.
  String? error;

  String get fileName => fileNameOf(path);

  int get highlightCount =>
      segments.where((segment) => segment.verdict == AiVerdict.highlight).length;

  /// The segments worth writing into a project: everything but 「普通」.
  int get keptCount =>
      segments.where((segment) => segment.verdict != AiVerdict.ordinary).length;
}

/// The highlight total across the batch — what 「高光片段 · 共 N 段」 shows.
///
/// A skipped file contributes nothing: its group is shown as 已跳过 and its
/// partial candidates never reach the list or the project file.
int totalHighlights(Iterable<AiFileResult> files) => files.fold(
    0, (sum, file) => sum + (file.skipped ? 0 : file.highlightCount));

/// The kept-segment total across the batch (what a save would write).
int totalKept(Iterable<AiFileResult> files) =>
    files.fold(0, (sum, file) => sum + (file.skipped ? 0 : file.keptCount));

/// One file's row group in the 「高光片段」 list.
///
/// A file with no highlight keeps its group with an empty [segments] so the
/// user can see it was analysed (「无检出高光」); a skipped file keeps it too.
class AiHighlightGroup {
  const AiHighlightGroup({
    required this.path,
    required this.segments,
    this.skipped = false,
  });

  /// The file these rows belong to — the preview plays **this** path.
  final String path;
  final List<AiSegment> segments;
  final bool skipped;

  String get fileName => fileNameOf(path);

  int get count => segments.length;
}

/// The 「高光片段」 list, grouped by file and in batch order — only
/// `verdict == highlight` rows, files with none included.
List<AiHighlightGroup> highlightGroups(List<AiFileResult> files) => [
      for (final file in files)
        AiHighlightGroup(
          path: file.path,
          segments: [
            for (final segment in file.segments)
              if (segment.verdict == AiVerdict.highlight) segment,
          ],
          skipped: file.skipped,
        ),
    ];

/// Every file's kept segments in **one** `.hlcproj` (docs/hlcproj_format.md):
///
/// * `sources[]` — one entry per analysed (non-skipped) file, ids
///   `src-ai-1..n`, each carrying its own `filePath` / `durationMs` / size;
/// * `timeslots[]` — ids `slot-ai-1..m` across the whole batch, each
///   `videoSourceId` pointing at **its own** file, `inPointMs`/`outPointMs`
///   from the candidate, `rating` 4 for a highlight and 2 for a candidate the
///   model never judged, `filename` = that file's base name;
/// * 「普通」 never reaches the file (same rule as the single-video writer);
/// * a skipped file contributes no source: it was never analysed, so there is
///   no durationMs to write.
///
/// [describe] resolves the caption for slot [index] (1-based) — the dialog
/// passes the 「AI 候选 N」 fallback there, the probe passes its own.
Map<String, dynamic> buildAiProjectJson({
  required List<AiFileResult> files,
  required String name,
  required String date,
  String Function(int index, AiSegment segment)? describe,
}) {
  final sources = <Map<String, dynamic>>[];
  final timeslots = <Map<String, dynamic>>[];
  var slots = 0;
  for (final file in files) {
    if (file.skipped) continue;
    final sourceId = 'src-ai-${sources.length + 1}';
    sources.add({
      'id': sourceId,
      'filePath': file.path,
      'durationMs': file.durationMs,
      'width': file.width,
      'height': file.height,
    });
    final kept = [
      for (final segment in file.segments)
        if (segment.verdict != AiVerdict.ordinary) segment,
    ]..sort((a, b) => a.startMs.compareTo(b.startMs));
    for (final segment in kept) {
      slots++;
      timeslots.add({
        'id': 'slot-ai-$slots',
        'videoSourceId': sourceId,
        'inPointMs': segment.startMs,
        'outPointMs': segment.endMs,
        'description':
            describe?.call(slots, segment) ?? segment.description,
        'rating': segment.verdict == AiVerdict.highlight ? 4 : 2,
        'filename': file.fileName,
      });
    }
  }
  return {
    'name': name,
    'date': date,
    'sources': sources,
    'timeslots': timeslots,
  };
}

/// The `file i/n ` prefix every batch-scoped log line carries; empty for a
/// single-video run, so those lines stay byte-identical to the old format
/// (docs/ai_marking.md §Logging).
String fileLogPrefix(int index, int total) =>
    total > 1 ? 'file ${index + 1}/$total ' : '';

/// The closing `[ai-marking] batch done ...` line
/// (docs/ai_marking.md §Logging); field order is fixed:
/// `files ok skipped highlight_total prompt_tok elapsed`.
///
/// `files` is how many were selected, `ok`/`skipped` how many were actually
/// analysed or given up on — an interrupted batch leaves the difference
/// unaccounted, which is the signal that 取消/401 stopped it.
String batchDoneLine({
  required int files,
  required int ok,
  required int skipped,
  required int highlightTotal,
  required int promptTokens,
  required int elapsedMs,
}) =>
    'batch done files=$files ok=$ok skipped=$skipped'
    ' highlight_total=$highlightTotal prompt_tok=$promptTokens'
    ' elapsed=${(elapsedMs / 1000).round()}s';
