import 'package:highlight_creator/domain/entities/video_source.dart';

/// Abstract repository for video source operations.
abstract class VideoRepository {
  /// Add a video source to a project.
  Future<VideoSource> add(VideoSource source);

  /// Get all sources for a project.
  Future<List<VideoSource>> listByProject(String projectId);

  /// Delete a video source and its cached thumbnails.
  Future<void> delete(String id);
}
