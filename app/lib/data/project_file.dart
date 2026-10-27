/// The date a project belongs to.
///
/// A Top-5 reel's period (week 43, October, 2026) comes from the project, not
/// from the clock: reopening the project recorded on Oct 21 must still mean
/// week 43 even in week 44. The project row carries that date in `createdAt`,
/// and this file decides what to put there when a project is created or
/// loaded.
///
/// Two sources, in order:
///   1. the `date` key of the `.hlcproj` (`2026-10-21`),
///   2. the file name, because autosave names files after the project date.
library;

/// `2026-10-21` anywhere in a file name, as a date at local midnight.
///
/// Returns null when the name has no usable date, so the caller can fall back
/// to "today" instead of inventing one.
DateTime? projectDateFromFileName(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final match = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(name);
  if (match == null) return null;
  return _date(
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
  );
}

/// The `date` entry of an `.hlcproj`, falling back to the file name.
DateTime? projectDateOf(Map<String, dynamic> json, String? filePath) {
  final raw = json['date'];
  if (raw is String) {
    final parsed = projectDateFromFileName(raw);
    if (parsed != null) return parsed;
  }
  return filePath == null ? null : projectDateFromFileName(filePath);
}

/// The canonical `date` value written into an `.hlcproj`.
String projectDateValue(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}

/// Reject 2026-13-45 and 2026-02-30: `DateTime` would silently roll them over.
DateTime? _date(int year, int month, int day) {
  if (year < 1970 || year > 2200) return null;
  if (month < 1 || month > 12) return null;
  if (day < 1 || day > 31) return null;
  final date = DateTime(year, month, day);
  if (date.year != year || date.month != month || date.day != day) return null;
  return date;
}
