/// Categories of effect presets.
enum PresetCategory {
  color,
  blur,
  transition,
  text,
  export,
}

/// A saved effect or export preset.
class Preset {
  final String id;
  final String name;
  final PresetCategory category;
  final Map<String, dynamic> parameters;
  final bool isBuiltIn;
  final String? userId;
  final DateTime updatedAt;

  const Preset({
    required this.id,
    required this.name,
    required this.category,
    required this.parameters,
    this.isBuiltIn = false,
    this.userId,
    required this.updatedAt,
  });

  Preset copyWith({
    String? id,
    String? name,
    PresetCategory? category,
    Map<String, dynamic>? parameters,
    bool? isBuiltIn,
    String? userId,
    DateTime? updatedAt,
  }) {
    return Preset(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      parameters: parameters ?? this.parameters,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      userId: userId ?? this.userId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
