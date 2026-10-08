/// Metadata for an imported source video file.
class VideoSource {
  final String id;
  final String projectId;
  final String filePath;
  final int durationMs;
  final int width;
  final int height;
  final String codecName;
  final double fps;
  final String? thumbnailPath;
  final DateTime createdAt;

  const VideoSource({
    required this.id,
    required this.projectId,
    required this.filePath,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.codecName,
    required this.fps,
    this.thumbnailPath,
    required this.createdAt,
  });

  Duration get duration => Duration(milliseconds: durationMs);

  VideoSource copyWith({
    String? id,
    String? projectId,
    String? filePath,
    int? durationMs,
    int? width,
    int? height,
    String? codecName,
    double? fps,
    String? thumbnailPath,
    DateTime? createdAt,
  }) {
    return VideoSource(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      width: width ?? this.width,
      height: height ?? this.height,
      codecName: codecName ?? this.codecName,
      fps: fps ?? this.fps,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
