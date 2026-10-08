import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/app_paths.dart';

/// Verify all app output folders live under %USERPROFILE%\HighlightCreator.
void main() {
  test('AppPaths resolve under %USERPROFILE%\\HighlightCreator', () {
    final home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'];
    expect(home, isNotNull, reason: 'USERPROFILE must be set');
    final sep = Platform.pathSeparator;
    expect(AppPaths.baseDir, '$home${sep}HighlightCreator');
    expect(AppPaths.templatesDir,
        '$home${sep}HighlightCreator${sep}templates');
    expect(AppPaths.resultsDir,
        '$home${sep}HighlightCreator${sep}results');
    expect(AppPaths.databasePath,
        '$home${sep}HighlightCreator${sep}highlight_creator.sqlite');
    expect(AppPaths.settingsPath,
        '$home${sep}HighlightCreator${sep}settings.json');
    expect(AppPaths.templateRegistryPath,
        '$home${sep}HighlightCreator${sep}templates.json');
  });

  test('base dir and templates dir are created on access', () {
    AppPaths.ensureBaseDir();
    expect(Directory(AppPaths.baseDir).existsSync(), isTrue);
    expect(Directory(AppPaths.templatesDir).existsSync(), isTrue);
  });
}
