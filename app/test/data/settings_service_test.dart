// Regression tests for SettingsService persistence and the startup load
// race that made the beginner guide ignore the "don't auto popup" setting.
//
// The race: the first frame starts the language load (file read in flight),
// then the post-frame callback reads guideAutoShow. The second read must
// await the in-flight load instead of seeing empty data and defaulting to
// auto-show = true.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/settings_service.dart';

void main() {
  late Directory tempDir;
  late String settingsPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hc_settings_test_');
    settingsPath = '${tempDir.path}${Platform.pathSeparator}settings.json';
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('concurrent first reads honor persisted guideAutoShow=false',
      () async {
    File(settingsPath).writeAsStringSync(jsonEncode({'guideAutoShow': false}));

    final svc = SettingsService(path: settingsPath);
    // App startup order: language load starts during the first build, then
    // the guide auto-show check fires while the file read is still in
    // flight.
    final languageFuture = svc.language;
    final autoShow = await svc.guideAutoShow;

    expect(autoShow, isFalse);
    expect(await languageFuture, 'English');
  });

  test('concurrent first reads honor persisted language=中文', () async {
    File(settingsPath).writeAsStringSync(jsonEncode({'language': '中文'}));

    final svc = SettingsService(path: settingsPath);
    final autoShowFuture = svc.guideAutoShow;
    final lang = await svc.language;

    expect(lang, '中文');
    expect(await autoShowFuture, isTrue); // key absent from file -> default
  });

  test('guideAutoShow=false persists and survives a fresh instance', () async {
    final svc = SettingsService(path: settingsPath);
    await svc.setGuideAutoShow(false);

    final svc2 = SettingsService(path: settingsPath);
    expect(await svc2.guideAutoShow, isFalse);

    final raw = jsonDecode(File(settingsPath).readAsStringSync())
        as Map<String, dynamic>;
    expect(raw['guideAutoShow'], isFalse);
  });

  test('defaults to auto-show when the settings file is absent', () async {
    final svc = SettingsService(path: settingsPath);
    expect(await svc.guideAutoShow, isTrue);
  });
}
