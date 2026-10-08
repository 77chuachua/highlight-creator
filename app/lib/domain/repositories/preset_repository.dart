import 'package:highlight_creator/domain/entities/preset.dart';

/// Abstract repository for effect and export presets.
abstract class PresetRepository {
  /// Save a new or updated preset.
  Future<Preset> save(Preset preset);

  /// Get a preset by ID.
  Future<Preset?> getById(String id);

  /// List presets by category.
  Future<List<Preset>> listByCategory(PresetCategory category);

  /// List built-in presets.
  Future<List<Preset>> listBuiltIn();

  /// List user-created presets.
  Future<List<Preset>> listByUser(String userId);

  /// Delete a preset.
  Future<void> delete(String id);
}
