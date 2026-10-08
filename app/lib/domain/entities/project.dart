import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';

/// Domain entity representing a highlight project.
class Project {
  final String id;
  final String name;
  final String userId;
  final List<Timeslot> timeslots;
  final List<VideoSource> sources;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Project({
    required this.id,
    required this.name,
    required this.userId,
    this.timeslots = const [],
    this.sources = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  /// Total duration of all timeslots combined.
  Duration get totalDuration {
    return timeslots.fold(
      Duration.zero,
      (sum, slot) => sum + slot.duration,
    );
  }

  Project copyWith({
    String? id,
    String? name,
    String? userId,
    List<Timeslot>? timeslots,
    List<VideoSource>? sources,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Project(
      id: id ?? this.id,
      name: name ?? this.name,
      userId: userId ?? this.userId,
      timeslots: timeslots ?? this.timeslots,
      sources: sources ?? this.sources,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
