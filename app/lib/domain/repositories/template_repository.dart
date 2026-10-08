import 'package:highlight_creator/domain/entities/template.dart';

/// Abstract repository for startup and transition video templates.
abstract class TemplateRepository {
  /// Get a template by ID.
  Future<Template?> getById(String id);

  /// List all templates.
  Future<List<Template>> listAll();

  /// List templates of a given [type].
  Future<List<Template>> listByType(TemplateType type);

  /// Save (insert or update) a template.
  Future<Template> save(Template template);

  /// Delete a template.
  Future<void> delete(String id);
}
