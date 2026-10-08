/// Types of templates used in the highlight pipeline.
enum TemplateType {
  startup,
  transition,
  ending,
  backgroundMusic,
}

/// A video template for startup intro or transition effects.
///
/// The [path] can be a local file path, a file:// URI, or an https:// URL.
class Template {
  final String id;
  final String name;
  final String path;
  final TemplateType type;
  final int? fontSize;
  final String? fontColor;
  final String? fontPath;
  final String? textPosition;
  final String? title;
  final bool showText;

  const Template({
    required this.id,
    required this.name,
    required this.path,
    required this.type,
    this.fontSize,
    this.fontColor,
    this.fontPath,
    this.textPosition,
    this.title,
    this.showText = true,
  });

  Template copyWith({
    String? id,
    String? name,
    String? path,
    TemplateType? type,
    int? fontSize,
    String? fontColor,
    String? fontPath,
    String? textPosition,
    String? title,
    bool? showText,
  }) {
    return Template(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      type: type ?? this.type,
      fontSize: fontSize ?? this.fontSize,
      fontColor: fontColor ?? this.fontColor,
      fontPath: fontPath ?? this.fontPath,
      textPosition: textPosition ?? this.textPosition,
      title: title ?? this.title,
      showText: showText ?? this.showText,
    );
  }
}