import 'dart:convert';
import 'dart:io' show Directory, File, Platform;

import 'package:uuid/uuid.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/domain/repositories/template_repository.dart';

/// Template repository with JSON file persistence for user-added templates.
///
/// Default templates (startup, transition, ending) are always inserted
/// in-memory.  User-added templates are persisted to a JSON file so they
/// survive application restarts.
class TemplateRepositoryImpl implements TemplateRepository {
  final Map<String, Template> _templates = {};
  final Uuid _uuid = const Uuid();
  bool _defaultsInserted = false;
  final String? _storagePath;

  TemplateRepositoryImpl({String? storagePath}) : _storagePath = storagePath;

  String get _effectiveStoragePath =>
      _storagePath ?? _resolveDefaultStoragePath();

  static String _resolveDefaultStoragePath() {
    return AppPaths.templateRegistryPath;
  }

  /// Resolve a potentially relative path to absolute using the project root.
  static String _resolveToAbsolute(String path) {
    if (path.isEmpty) return path;
    if (File(path).isAbsolute) return path;

    // Try to locate the project root
    var dir = Directory.current;
    while (true) {
      if (File('${dir.path}${Platform.pathSeparator}AGENTS.md').existsSync() ||
          Directory('${dir.path}${Platform.pathSeparator}app').existsSync()) {
        return '${dir.path}${Platform.pathSeparator}$path';
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    // Fallback: resolve relative to current directory
    return File(path).absolute.path;
  }

  void _ensureDefaults() {
    if (_defaultsInserted) return;
    _defaultsInserted = true;

    _loadFromDisk();

    // Remove templates whose file paths no longer exist on disk.
    _removeInvalidTemplates();
  }

  /// Remove templates whose file paths are non-empty and don't exist on disk.
  void _removeInvalidTemplates() {
    final toRemove = <String>[];
    for (final entry in _templates.entries) {
      final path = entry.value.path;
      // Skip default templates with empty paths — they use project-relative fallbacks.
      if (path.isEmpty && entry.key.startsWith('default_')) continue;
      // Skip templates with empty paths (user-created but not yet configured).
      if (path.isEmpty) continue;
      if (!File(path).existsSync()) {
        toRemove.add(entry.key);
      }
    }
    for (final id in toRemove) {
      _templates.remove(id);
    }
    if (toRemove.isNotEmpty) {
      _persistToDisk();
    }
  }

  void _loadFromDisk() {
    try {
      final file = File(_effectiveStoragePath);
      if (file.existsSync()) {
        final json = jsonDecode(file.readAsStringSync()) as List;
        for (final raw in json) {
          final item = raw as Map<String, dynamic>;
          final rawPath = item['path'] as String;
          // Convert relative paths to absolute.
          final absolutePath = _resolveToAbsolute(rawPath);
          final t = Template(
            id: item['id'] as String,
            name: item['name'] as String,
            path: absolutePath,
            type: TemplateType.values.firstWhere(
              (e) => e.name == item['type'],
              orElse: () => TemplateType.startup,
            ),
            fontSize: item['fontSize'] as int?,
            fontColor: item['fontColor'] as String?,
            fontPath: item['fontPath'] as String?,
            textPosition: item['textPosition'] as String?,
            title: item['title'] as String?,
            showText: item['showText'] as bool? ?? true,
          );
          if (!_templates.containsKey(t.id)) {
            _templates[t.id] = t;
          }
        }
      }
    } catch (_) {}
  }

  void _persistToDisk() {
    try {
      final file = File(_effectiveStoragePath);
      file.parent.createSync(recursive: true);
      final userTemplates = _templates.values
          .where((t) => !t.id.startsWith('default_'))
          .map((t) => {
                'id': t.id,
                'name': t.name,
                'path': t.path,
                'type': t.type.name,
                if (t.fontSize != null) 'fontSize': t.fontSize,
                if (t.fontColor != null) 'fontColor': t.fontColor,
                if (t.fontPath != null) 'fontPath': t.fontPath,
                if (t.textPosition != null) 'textPosition': t.textPosition,
                if (t.title != null) 'title': t.title,
                if (!t.showText) 'showText': t.showText,
              })
          .toList();
      file.writeAsStringSync(jsonEncode(userTemplates));
    } catch (_) {}
  }

  @override
  Future<Template?> getById(String id) async {
    _ensureDefaults();
    return _templates[id];
  }

  @override
  Future<List<Template>> listAll() async {
    _ensureDefaults();
    return _templates.values.toList();
  }

  @override
  Future<List<Template>> listByType(TemplateType type) async {
    _ensureDefaults();
    return _templates.values.where((t) => t.type == type).toList();
  }

  @override
  Future<Template> save(Template template) async {
    _ensureDefaults();
    final id = template.id.isEmpty ? _uuid.v4() : template.id;

    // Ensure the path is absolute.
    var path = template.path;
    if (path.isNotEmpty && !File(path).isAbsolute) {
      path = _resolveToAbsolute(path);
    }

    // Dedupe: one logical template per (type + file). When saving a new
    // template, reuse an existing record pointing at the same file instead
    // of creating a second copy of the settings.
    String effectiveId = id;
    if (template.id.isEmpty && path.isNotEmpty) {
      final norm = _normalizePath(path);
      for (final t in _templates.values) {
        if (t.type == template.type && _normalizePath(t.path) == norm) {
          effectiveId = t.id;
          break;
        }
      }
    }

    final t = template.copyWith(id: effectiveId, path: path);
    _templates[effectiveId] = t;
    _persistToDisk();
    return t;
  }

  /// Case- and separator-insensitive path key for duplicate detection.
  static String _normalizePath(String p) => p.toLowerCase().replaceAll('\\', '/');

  @override
  Future<void> delete(String id) async {
    _ensureDefaults();
    _templates.remove(id);
    _persistToDisk();
  }
}