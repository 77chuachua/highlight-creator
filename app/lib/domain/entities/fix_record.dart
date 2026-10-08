/// Domain entity representing a completed fix record.
class FixRecord {
  final String id;
  final String description;
  final String filesChanged; // comma-separated paths
  final DateTime resolvedAt;

  const FixRecord({
    required this.id,
    required this.description,
    this.filesChanged = '',
    required this.resolvedAt,
  });

  FixRecord copyWith({
    String? id,
    String? description,
    String? filesChanged,
    DateTime? resolvedAt,
  }) {
    return FixRecord(
      id: id ?? this.id,
      description: description ?? this.description,
      filesChanged: filesChanged ?? this.filesChanged,
      resolvedAt: resolvedAt ?? this.resolvedAt,
    );
  }
}
