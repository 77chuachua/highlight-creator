import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/voice_pack_store.dart';
import 'package:highlight_creator/domain/entities/voice_pack.dart';
import 'package:highlight_creator/services/local_voice_service.dart';

/// The cloning engine is optional: without it the app has to say how to
/// install it instead of failing silently.
void main() {
  test('without the engine installed, speaking explains how to install it',
      () async {
    final dir = Directory.systemTemp.createTempSync('clone_');
    addTearDown(() => dir.deleteSync(recursive: true));
    AppPaths.overrideBaseDir = dir.path;
    addTearDown(() => AppPaths.overrideBaseDir = null);

    expect(LocalVoiceService.isInstalled, isFalse);

    final result = await LocalVoiceService.speak(
      text: '任意文字',
      promptText: '提示词',
      reference: '${dir.path}${Platform.pathSeparator}ref.wav',
      output: '${dir.path}${Platform.pathSeparator}out.wav',
    );
    expect(result.ok, isFalse);
    expect(result.error, contains('setup.bat'));
  });

  group('without the plugin, nothing else breaks', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('clone_none_');
      AppPaths.overrideBaseDir = root.path;
    });

    tearDown(() {
      AppPaths.overrideBaseDir = null;
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('every plugin lookup answers instead of throwing', () {
      // The Top-5 dialog calls these on open; an exception here would take the
      // whole reel flow down instead of just hiding "my own voice".
      expect(LocalVoiceService.manifest, isNull);
      expect(LocalVoiceService.engineName, isEmpty);
      expect(LocalVoiceService.studioPath, isNull);
      expect(LocalVoiceService.hasStudio, isFalse);
      expect(LocalVoiceService.isInstalled, isFalse);
      expect(LocalVoiceService.installHint, contains('setup.bat'));
    });

    test('imported voice packs are still listed', () {
      // Packs are plain folders; they stay visible (and importable) even when
      // there is no engine to speak them.
      final pack = Directory(
          '${AppPaths.voicesDir}${Platform.pathSeparator}甲${VoicePack.folderSuffix}')
        ..createSync(recursive: true);
      File('${pack.path}${Platform.pathSeparator}${VoicePack.referenceName}')
          .writeAsBytesSync(List<int>.filled(512, 1));

      final packs = const VoicePackStore().list();
      expect(packs, hasLength(1));
      expect(packs.single.name, '甲');
      expect(LocalVoiceService.isInstalled, isFalse);
    });
  });
}
