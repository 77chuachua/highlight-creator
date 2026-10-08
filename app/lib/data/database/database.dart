import 'dart:io' show File;
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/database/tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    UserProfiles,
    Projects,
    VideoSources,
    Timeslots,
    Templates,
    Fixes,
    Presets,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._(super.e);

  static const int _schemaVersion = 4;

  /// File-based database at an explicit path (for scripts / direct access).
  factory AppDatabase.file(String path) {
    return AppDatabase._(DatabaseConnection(
      NativeDatabase(File(path)),
    ).executor);
  }

  /// In-memory database (for testing / fallback).
  factory AppDatabase.memory() {
    return AppDatabase._(DatabaseConnection(
      NativeDatabase.memory(),
    ).executor);
  }

  /// File-based database under %USERPROFILE%\HighlightCreator.
  static Future<AppDatabase> create() async {
    AppPaths.ensureBaseDir();
    return AppDatabase._(DatabaseConnection(
      NativeDatabase(File(AppPaths.databasePath)),
    ).executor);
  }

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // Schema v4: added Fixes table. For new databases it is created
        // via createAll. Production drift codegen will add the real migration.
      },
    );
  }

  @override
  int get schemaVersion => _schemaVersion;
}