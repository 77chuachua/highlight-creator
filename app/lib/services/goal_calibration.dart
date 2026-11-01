/// Goal calibration: the user draws one or two boxes around the goals on a
/// single frame, and every later step uses them to crop-zoom the goal areas
/// before the vision model sees them (docs/ai_marking.md §球门标定).
///
/// The boxes are stored normalized (0..1 of the frame width/height) so a
/// calibration survives resolution changes, one JSON file per source:
///
/// `%USERPROFILE%\HighlightCreator\calibration\<sha1(源文件绝对路径)>.json`
///
/// A missing, unreadable or malformed file is not an error: callers get `null`
/// and the analysis behaves exactly as if nothing was calibrated. Nothing here
/// touches the screen-motion channel — this round only reads the boxes when
/// building the VLM crops (`ai_marking_service.dart`).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:highlight_creator/data/app_paths.dart';

/// One box on the frame, all four values normalized to 0..1 relative to the
/// frame width/height. Kept resolution-independent on purpose: a 4K source and
/// its 720p proxy produce the same crop.
class NormRect {
  const NormRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  /// The box a pointer drag covers: corners in any order, clamped to the frame.
  factory NormRect.fromDrag(
      double startX, double startY, double endX, double endY) {
    final left = _unit(math.min(startX, endX));
    final right = _unit(math.max(startX, endX));
    final top = _unit(math.min(startY, endY));
    final bottom = _unit(math.max(startY, endY));
    return NormRect(x: left, y: top, w: right - left, h: bottom - top)
        .normalized();
  }

  /// A box smaller than this on either side is a stray click, not a goal.
  static const double minSide = 0.01;

  final double x;
  final double y;
  final double w;
  final double h;

  double get right => x + w;
  double get bottom => y + h;

  bool get isUsable => w.isFinite && h.isFinite && w >= minSide && h >= minSide;

  /// Clamp into the frame, keeping `x+w <= 1` and `y+h <= 1`.
  NormRect normalized() {
    final nx = _unit(x);
    final ny = _unit(y);
    final nw = w.isFinite ? w.clamp(0.0, 1.0 - nx).toDouble() : 0.0;
    final nh = h.isFinite ? h.clamp(0.0, 1.0 - ny).toDouble() : 0.0;
    return NormRect(x: nx, y: ny, w: nw, h: nh);
  }

  /// The crop filter for this box, before `scale`/`tile`.
  ///
  /// `crop=w:h:x:y` with `floor(.. / 2) * 2` on both sides: H.264/JPEG chroma
  /// needs even dimensions, and a normalized width of `0.371` on an odd-width
  /// frame would otherwise land on an odd pixel count. The x/y offsets only
  /// need `floor`, they do not affect chroma. Order in the caller is
  /// `fps -> crop -> scale -> tile`.
  String get cropFilter {
    final rect = normalized();
    return 'crop=floor(iw*${_fixed(rect.w)}/2)*2'
        ':floor(ih*${_fixed(rect.h)}/2)*2'
        ':floor(iw*${_fixed(rect.x)})'
        ':floor(ih*${_fixed(rect.y)})';
  }

  /// [cropFilter] evaluated for one frame size, as pixels.
  ///
  /// Lives beside [cropFilter] so the probe can prove the floor-to-even maths
  /// on an odd-sized frame without decoding a video. Keep the two in sync.
  ({int x, int y, int width, int height}) cropPixels(
      int frameWidth, int frameHeight) {
    final rect = normalized();
    return (
      x: (frameWidth * rect.x).floor(),
      y: (frameHeight * rect.y).floor(),
      width: (frameWidth * rect.w / 2).floor() * 2,
      height: (frameHeight * rect.h / 2).floor() * 2,
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  /// Null for anything that is not a usable box (missing keys, out of range,
  /// a zero-sized drag).
  static NormRect? tryParse(Object? json) {
    if (json is! Map) return null;
    final x = _number(json['x']);
    final y = _number(json['y']);
    final w = _number(json['w']);
    final h = _number(json['h']);
    if (x == null || y == null || w == null || h == null) return null;
    final rect = NormRect(x: x, y: y, w: w, h: h).normalized();
    return rect.isUsable ? rect : null;
  }

  static double _unit(double value) =>
      value.isFinite ? value.clamp(0.0, 1.0).toDouble() : 0.0;

  static double? _number(Object? value) =>
      value is num ? value.toDouble() : null;

  /// Six decimals: enough for a pixel on an 8K frame, short enough to read.
  static String _fixed(double value) => value.toStringAsFixed(6);

  @override
  bool operator ==(Object other) =>
      other is NormRect &&
      other.x == x &&
      other.y == y &&
      other.w == w &&
      other.h == h;

  @override
  int get hashCode => Object.hash(x, y, w, h);

  @override
  String toString() =>
      'NormRect(x=${x.toStringAsFixed(3)}, y=${y.toStringAsFixed(3)}, '
      'w=${w.toStringAsFixed(3)}, h=${h.toStringAsFixed(3)})';
}

/// One source's calibration: up to two goal boxes plus where the frame came
/// from. `sourceKey` is [GoalCalibration.keyFor] of the source path, which is
/// also the JSON file name.
class GoalCalibration {
  GoalCalibration({
    required this.sourceKey,
    required List<NormRect> rects,
    this.frameTimeMs = 0,
    DateTime? updatedAt,
  })  : rects = List<NormRect>.unmodifiable(_clean(rects)),
        updatedAt = updatedAt ?? DateTime.now();

  /// 球门 1 / 球门 2. A third drag replaces the second box.
  static const int maxGoals = 2;

  /// The same formats AI 打点 accepts (`ai_marking_dialog.dart`).
  static const List<String> videoExtensions = ['mp4', 'mov', 'mkv'];

  final String sourceKey;
  final List<NormRect> rects;

  /// Where the frame the boxes were drawn on came from, ms into the source.
  final int frameTimeMs;

  final DateTime updatedAt;

  bool get isUsable => rects.isNotEmpty;

  /// `%USERPROFILE%\HighlightCreator\calibration`.
  static String get calibrationDir =>
      '${AppPaths.baseDir}${Platform.pathSeparator}calibration';

  /// The file name is the full SHA-1 of the source's absolute path, so one
  /// source has exactly one calibration even after a restart.
  static String keyFor(String sourcePath) =>
      sha1.convert(utf8.encode(File(sourcePath).absolute.path)).toString();

  static String pathForKey(String sourceKey) =>
      '${calibrationDir}${Platform.pathSeparator}$sourceKey.json';

  /// Null when this source was never calibrated, or when the file is missing,
  /// unreadable or malformed. Callers must treat all of those the same.
  static GoalCalibration? load(String sourcePath) {
    final key = keyFor(sourcePath);
    try {
      final file = File(pathForKey(key));
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      final rects = <NormRect>[];
      final rawRects = decoded['rects'];
      if (rawRects is List) {
        for (final entry in rawRects) {
          final rect = NormRect.tryParse(entry);
          if (rect != null) rects.add(rect);
        }
      }
      if (rects.isEmpty) return null;
      final rawTime = decoded['frameTimeMs'];
      return GoalCalibration(
        sourceKey: key,
        rects: rects,
        frameTimeMs: rawTime is num ? rawTime.toInt() : 0,
        updatedAt: DateTime.tryParse('${decoded['updatedAt'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      // Broken file / no permission: behave as "not calibrated".
      return null;
    }
  }

  /// Best-effort write; false only means "this run will behave as uncalibrated".
  bool save() {
    try {
      Directory(calibrationDir).createSync(recursive: true);
      File(pathForKey(sourceKey)).writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(toJson()));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Copy the saved calibration of [sourcePath] to every other mp4/mov/mkv in
  /// the same folder (the camera did not move, so one box fits the whole
  /// session). Returns how many siblings were written; 0 when the source is not
  /// calibrated or the folder cannot be read.
  ///
  /// `frameTimeMs` is left at 0 on purpose: a sibling is a different slice of
  /// the match, so the 30 % frame that fits it is not the primary's frame. The
  /// dialog falls back to 30 % of each file when this is 0.
  static int applyToSiblings(String sourcePath) {
    final calibration = load(sourcePath);
    if (calibration == null) return 0;
    return _writeSiblings(sourcePath, calibration.rects);
  }

  static int _writeSiblings(String sourcePath, List<NormRect> rects) {
    final clean = _clean(rects).toList(growable: false);
    if (clean.isEmpty) return 0;
    var written = 0;
    try {
      final source = File(sourcePath).absolute;
      final now = DateTime.now();
      for (final entry in source.parent.listSync(followLinks: false)) {
        if (entry is! File) continue;
        if (entry.path.toLowerCase() == source.path.toLowerCase()) continue;
        final name = entry.path.split(RegExp(r'[\\/]')).last;
        final dot = name.lastIndexOf('.');
        if (dot <= 0) continue;
        if (!videoExtensions.contains(name.substring(dot + 1).toLowerCase())) {
          continue;
        }
        final sibling = GoalCalibration(
          sourceKey: keyFor(entry.path),
          rects: clean,
          updatedAt: now,
        );
        if (sibling.save()) written++;
      }
    } catch (_) {
      // A folder we cannot list simply gets no siblings.
    }
    return written;
  }

  Map<String, dynamic> toJson() => {
        'sourceKey': sourceKey,
        'rects': [for (final rect in rects) rect.toJson()],
        'frameTimeMs': frameTimeMs,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static Iterable<NormRect> _clean(Iterable<NormRect> rects) => rects
      .map((rect) => rect.normalized())
      .where((rect) => rect.isUsable)
      .take(maxGoals);
}
