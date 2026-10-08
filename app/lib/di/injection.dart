import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:riverpod/riverpod.dart';
import 'package:highlight_creator/data/database/database.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/data/repositories/user_repository_impl.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/data/repositories/preset_repository_impl.dart';
import 'package:highlight_creator/data/repositories/template_repository_impl.dart';
import 'package:highlight_creator/data/repositories/timeslot_repository_impl.dart';
import 'package:highlight_creator/data/repositories/fix_repository_impl.dart';
import 'package:highlight_creator/domain/entities/template.dart' as domain;
import 'package:highlight_creator/domain/repositories/user_repository.dart';
import 'package:highlight_creator/domain/repositories/project_repository.dart';
import 'package:highlight_creator/domain/repositories/preset_repository.dart';
import 'package:highlight_creator/domain/repositories/template_repository.dart';
import 'package:highlight_creator/domain/repositories/timeslot_repository.dart';
import 'package:highlight_creator/domain/repositories/fix_repository.dart';

final GetIt locator = GetIt.instance;

/// Initialize with file-based database. May fail if file system unavailable.
Future<void> initializeDependencies() async {
  final db = await AppDatabase.create();
  _register(db);
  await registerEmbeddedBgm();
}

/// Fallback: initialize with in-memory database (always works).
Future<void> initializeDependenciesFallback() async {
  final db = AppDatabase.memory();
  _register(db);
  await registerEmbeddedBgm();
}

void _register(AppDatabase db) {
  locator.registerSingleton<AppDatabase>(db);
  locator.registerLazySingleton<UserRepository>(() => UserRepositoryImpl());
  locator.registerLazySingleton<ProjectRepository>(() => ProjectRepositoryImpl());
  locator.registerLazySingleton<PresetRepository>(() => PresetRepositoryImpl());
  locator.registerLazySingleton<TemplateRepository>(() => TemplateRepositoryImpl());
  locator.registerLazySingleton<TimeslotRepository>(() => TimeslotRepositoryImpl());
  locator.registerLazySingleton<FixRepository>(() => FixRepositoryImpl(db));
}

final userRepositoryProvider = Provider<UserRepository>((ref) => locator<UserRepository>());
final projectRepositoryProvider = Provider<ProjectRepository>((ref) => locator<ProjectRepository>());
final presetRepositoryProvider = Provider<PresetRepository>((ref) => locator<PresetRepository>());
final templateRepositoryProvider = Provider<TemplateRepository>((ref) => locator<TemplateRepository>());
final timeslotRepositoryProvider = Provider<TimeslotRepository>((ref) => locator<TimeslotRepository>());
final fixRepositoryProvider = Provider<FixRepository>((ref) => locator<FixRepository>());
final databaseProvider = Provider<AppDatabase>((ref) => locator<AppDatabase>());

/// Register bg_music.mp3 (shipped beside ffmpeg) as an embedded background
/// music template at startup. No-op when the file is missing or already
/// registered. [ffmpegPath]/[repo] are injectable for tests.
Future<void> registerEmbeddedBgm({
  String? ffmpegPath,
  TemplateRepository? repo,
}) async {
  try {
    final bgm = ffmpegPath != null
        ? VideoProcessingService.resolveDefaultBgmFor(ffmpegPath)
        : await VideoProcessingService.resolveDefaultBgm();
    if (bgm == null) return;
    final r = repo ?? locator<TemplateRepository>();
    final existing = await r.listByType(domain.TemplateType.backgroundMusic);
    if (existing.any((t) => t.path == bgm)) return;
    await r.save(domain.Template(
      id: '',
      name: 'bg_music.mp3',
      path: bgm,
      type: domain.TemplateType.backgroundMusic,
    ));
  } catch (e) {
    debugPrint('registerEmbeddedBgm failed: $e');
  }
}