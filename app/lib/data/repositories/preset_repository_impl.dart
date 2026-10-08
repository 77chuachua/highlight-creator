import 'package:highlight_creator/domain/entities/preset.dart';
import 'package:highlight_creator/domain/repositories/preset_repository.dart';

/// Drift-backed implementation of PresetRepository.
/// Phase 0: placeholder. Full implementation comes in Phase 1 once drift codegen runs.
class PresetRepositoryImpl implements PresetRepository {
  @override
  Future<Preset> save(Preset preset) async {
    return preset; // TODO Phase 1: implement via db.upsertPreset()
  }

  @override
  Future<Preset?> getById(String id) async {
    return null; // TODO Phase 1: implement via db.getPreset()
  }

  @override
  Future<List<Preset>> listByCategory(PresetCategory category) async {
    return []; // TODO Phase 1: implement via db.listPresetsByCategory()
  }

  @override
  Future<List<Preset>> listBuiltIn() async {
    return []; // TODO Phase 1: implement via db.listBuiltInPresets()
  }

  @override
  Future<List<Preset>> listByUser(String userId) async {
    return []; // TODO Phase 1: implement via db.listPresetsByUser()
  }

  @override
  Future<void> delete(String id) async {
    // TODO Phase 1: implement via db.deletePreset()
  }
}
