/// A marked time region on a source video.
class Timeslot {
  final String id;
  final String projectId;
  final String videoSourceId;
  final int inPointMs;
  final int outPointMs;
  final String label;
  final int colorIndex;
  final int rating; // 0–5 stars
  final DateTime createdAt;

  /// New fields per issues.md structure.
  final String filename;
  final String description;
  final int elapse;   // duration in ms
  final bool remote;

  /// Zoom-in center point for remote timeslots (normalized 0.0–1.0).
  /// Set by the Zoom-in Point Configuration dialog.  When null, the
  /// default center+pan behaviour is used.
  final double? centerX;
  final double? centerY;

  const Timeslot({
    required this.id,
    required this.projectId,
    required this.videoSourceId,
    required this.inPointMs,
    required this.outPointMs,
    this.label = '',
    this.colorIndex = 0,
    this.rating = 0,
    required this.createdAt,
    this.filename = '',
    this.description = '',
    this.elapse = 0,
    this.remote = false,
    this.centerX,
    this.centerY,
  });

  Duration get inPoint => Duration(milliseconds: inPointMs);
  Duration get outPoint => Duration(milliseconds: outPointMs);
  Duration get duration => outPoint - inPoint;

  bool get isValid => inPointMs >= 0 && outPointMs > inPointMs;

  Timeslot copyWith({
    String? id,
    String? projectId,
    String? videoSourceId,
    int? inPointMs,
    int? outPointMs,
    String? label,
    int? colorIndex,
    int? rating,
    DateTime? createdAt,
    String? filename,
    String? description,
    int? elapse,
    bool? remote,
    double? centerX,
    double? centerY,
  }) {
    return Timeslot(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      videoSourceId: videoSourceId ?? this.videoSourceId,
      inPointMs: inPointMs ?? this.inPointMs,
      outPointMs: outPointMs ?? this.outPointMs,
      label: label ?? this.label,
      colorIndex: colorIndex ?? this.colorIndex,
      rating: rating ?? this.rating,
      createdAt: createdAt ?? this.createdAt,
      filename: filename ?? this.filename,
      description: description ?? this.description,
      elapse: elapse ?? this.elapse,
      remote: remote ?? this.remote,
      centerX: centerX ?? this.centerX,
      centerY: centerY ?? this.centerY,
    );
  }
}
