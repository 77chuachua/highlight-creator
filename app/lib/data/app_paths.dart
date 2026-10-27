import 'dart:io' show Directory, Platform;

/// Shared user-data locations for Highlight Creator.
///
/// On Windows all output folders live under `%USERPROFILE%\HighlightCreator`
/// so results, embedded templates, and the database survive in one place
/// regardless of where the app is installed (dev build, zip, installer, MSIX).
class AppPaths {
  /// Test seam: when set, every path resolves under this directory instead of
  /// the real user profile, keeping unit tests off the real results folder.
  static String? overrideBaseDir;

  static String get baseDir {
    final override = overrideBaseDir;
    if (override != null) return override;
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.systemTemp.path;
    return '$home${Platform.pathSeparator}HighlightCreator';
  }

  /// Embedded template videos (generated on first use).
  static String get templatesDir =>
      '$baseDir${Platform.pathSeparator}templates';

  /// Rendered highlight videos (Make output).
  static String get resultsDir => '$baseDir${Platform.pathSeparator}results';

  /// Temp directory for intermediate outputs (translate results, etc.).
  static String get tempDir => '$baseDir${Platform.pathSeparator}temp';

  /// App SQLite database.
  static String get databasePath =>
      '$baseDir${Platform.pathSeparator}highlight_creator.sqlite';

  /// App settings JSON.
  static String get settingsPath =>
      '$baseDir${Platform.pathSeparator}settings.json';

  /// User template registry JSON.
  static String get templateRegistryPath =>
      '$baseDir${Platform.pathSeparator}templates.json';

  /// The local voice-cloning engine: a Python virtual environment with the
  /// model, installed by tools/voice_clone/setup.bat.
  static String get voiceCloneDir =>
      '$baseDir${Platform.pathSeparator}voice_clone';

  /// Imported voice packs, one `<name>.voicepack` folder each.
  static String get voicesDir => '$baseDir${Platform.pathSeparator}voices';

  /// Ensure the base directory exists.
  static void ensureBaseDir() {
    Directory(baseDir).createSync(recursive: true);
  }
}
