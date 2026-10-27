import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/voice_pack_store.dart';
import 'package:highlight_creator/domain/entities/voice_pack.dart';

/// These paths are what a user's voice library lives in, and the migration is
/// the only thing standing between their existing recording and a lost voice.
void main() {
  const store = VoicePackStore();
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('hl_packs_');
    AppPaths.overrideBaseDir = root.path;
  });

  tearDown(() {
    AppPaths.overrideBaseDir = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Directory voicesDir() => Directory(AppPaths.voicesDir);

  void writeReference(Directory pack, {int bytes = 2048}) {
    pack.createSync(recursive: true);
    File('${pack.path}${Platform.pathSeparator}${VoicePack.referenceName}')
        .writeAsBytesSync(List<int>.filled(bytes, 1));
  }

  group('sanitize', () {
    test('strips what Windows forbids in a folder name', () {
      expect(VoicePackStore.sanitize('a/b\\c:d*e?f"g<h>i|j'), 'abcdefghij');
    });

    test('keeps Chinese and collapses spaces', () {
      expect(VoicePackStore.sanitize('  我的   声音  '), '我的 声音');
    });

    test('falls back when nothing is left', () {
      expect(VoicePackStore.sanitize('   '), '我的声音');
      expect(VoicePackStore.sanitize('///'), '我的声音');
    });
  });

  group('list', () {
    test('returns nothing when the folder does not exist', () {
      expect(store.list(), isEmpty);
    });

    test('reads packs and ignores folders without a reference', () {
      writeReference(Directory(
          '${voicesDir().path}${Platform.pathSeparator}甲${VoicePack.folderSuffix}'));
      Directory('${voicesDir().path}${Platform.pathSeparator}empty${VoicePack.folderSuffix}')
          .createSync(recursive: true);
      File('${voicesDir().path}${Platform.pathSeparator}notes.txt')
          .writeAsStringSync('x');

      final packs = store.list();
      expect(packs, hasLength(1));
      expect(packs.single.id, '甲');
      expect(packs.single.name, '甲');
    });

    test('a broken manifest falls back to the folder name', () {
      final dir = Directory(
          '${voicesDir().path}${Platform.pathSeparator}乙${VoicePack.folderSuffix}');
      writeReference(dir);
      File('${dir.path}${Platform.pathSeparator}${VoicePack.manifestName}')
          .writeAsStringSync('{ not json');

      final pack = store.list().single;
      expect(pack.name, '乙');
      expect(pack.hasStyle, isFalse);
    });

    test('reads the delivery settings the studio wrote', () {
      final dir = Directory(
          '${voicesDir().path}${Platform.pathSeparator}丁${VoicePack.folderSuffix}');
      writeReference(dir);
      // Exactly what studio.py writes into manifest.json.
      File('${dir.path}${Platform.pathSeparator}${VoicePack.manifestName}')
          .writeAsStringSync('{"schema":1,"name":"丁","speed":1.15,'
              '"instruct":"用激动的语气喊出这句话",'
              '"promptText":"这句话是参考录音真正说的"}');

      final pack = store.list().single;
      expect(pack.speed, 1.15);
      expect(pack.instruct, '用激动的语气喊出这句话');
      expect(pack.promptText, '这句话是参考录音真正说的');
      // And they survive a rewrite of the manifest.
      expect(pack.manifestJson, contains('"speed": 1.15'));
      expect(pack.manifestJson, contains('用激动的语气喊出这句话'));
    });

    test('an old pack without delivery settings stays plain', () {
      final dir = Directory(
          '${voicesDir().path}${Platform.pathSeparator}戊${VoicePack.folderSuffix}');
      writeReference(dir);
      final pack = store.list().single;
      expect(pack.speed, 1);
      expect(pack.instruct, isEmpty);
      expect(pack.promptText, isEmpty);
    });

    test('picks up an optional style.wav', () {
      final dir = Directory(
          '${voicesDir().path}${Platform.pathSeparator}丙${VoicePack.folderSuffix}');
      writeReference(dir);
      File('${dir.path}${Platform.pathSeparator}${VoicePack.styleName}')
          .writeAsBytesSync([1, 2, 3]);

      expect(store.list().single.hasStyle, isTrue);
    });
  });

  group('importDirectory', () {
    test('copies the reference and writes a manifest', () async {
      final source = Directory(
          '${root.path}${Platform.pathSeparator}incoming')
        ..createSync(recursive: true);
      File('${source.path}${Platform.pathSeparator}${VoicePack.referenceName}')
          .writeAsBytesSync(List<int>.filled(1024, 7));

      final pack = await store.importDirectory(source.path, name: '我的声音');
      expect(pack, isNotNull);
      expect(pack!.name, '我的声音');
      expect(File(pack.referencePath).existsSync(), isTrue);
      expect(pack.referencePath, endsWith(VoicePack.referenceName));

      final manifest =
          File('${pack.dir}${Platform.pathSeparator}${VoicePack.manifestName}');
      expect(manifest.existsSync(), isTrue);
      expect(manifest.readAsStringSync(), contains('"schema": 1'));

      // Re-reading from disk returns the same name.
      expect(store.list().single.name, '我的声音');
    });

    test('refuses a folder without reference.wav', () async {
      final source = Directory(
          '${root.path}${Platform.pathSeparator}useless')
        ..createSync(recursive: true);
      File('${source.path}${Platform.pathSeparator}other.wav')
          .writeAsBytesSync([1, 2, 3]);

      expect(await store.importDirectory(source.path), isNull);
      expect(store.list(), isEmpty);
    });

    test('never overwrites an existing pack of the same name', () async {
      final source = Directory(
          '${root.path}${Platform.pathSeparator}incoming')
        ..createSync(recursive: true);
      File('${source.path}${Platform.pathSeparator}${VoicePack.referenceName}')
          .writeAsBytesSync(List<int>.filled(1024, 7));

      final first = await store.importDirectory(source.path, name: '我的声音');
      final second = await store.importDirectory(source.path, name: '我的声音');

      expect(first!.dir, isNot(second!.dir));
      expect(second.name, '我的声音');
      expect(store.list(), hasLength(2));
    });

    test('carries a style reference across', () async {
      final source = Directory(
          '${root.path}${Platform.pathSeparator}incoming')
        ..createSync(recursive: true);
      File('${source.path}${Platform.pathSeparator}${VoicePack.referenceName}')
          .writeAsBytesSync([1, 2, 3]);
      final style = File('${root.path}${Platform.pathSeparator}demo.wav')
        ..writeAsBytesSync([4, 5, 6]);

      final pack =
          await store.importDirectory(source.path, name: 'X', styleSource: style.path);
      expect(pack!.hasStyle, isTrue);
      expect(File(pack.stylePath!).readAsBytesSync(), [4, 5, 6]);
    });
  });

  group('migrateLegacy', () {
    test('turns my_voice.wav into a pack and keeps the original', () {
      voicesDir().createSync(recursive: true);
      final legacy =
          File('${voicesDir().path}${Platform.pathSeparator}my_voice.wav')
            ..writeAsBytesSync(List<int>.filled(4096, 9));
      final style = File('${voicesDir().path}${Platform.pathSeparator}style.wav')
        ..writeAsBytesSync([1, 2, 3]);

      final pack = store.migrateLegacy(engine: 'cosyvoice2');
      expect(pack, isNotNull);
      expect(pack!.name, '我的声音');
      expect(pack.engine, 'cosyvoice2');
      expect(pack.hasStyle, isTrue);
      expect(File(pack.referencePath).lengthSync(), 4096);

      // The source files are still there: migration copies, never moves.
      expect(legacy.existsSync(), isTrue);
      expect(style.existsSync(), isTrue);
    });

    test('does nothing when there is no legacy recording', () {
      expect(store.migrateLegacy(), isNull);
      expect(store.list(), isEmpty);
    });

    test('is idempotent', () {
      voicesDir().createSync(recursive: true);
      File('${voicesDir().path}${Platform.pathSeparator}my_voice.wav')
          .writeAsBytesSync(List<int>.filled(2048, 3));

      final first = store.migrateLegacy();
      final second = store.migrateLegacy();
      expect(second?.dir, first?.dir, reason: 'a second run must not add a copy');
      expect(store.list(), hasLength(1));
    });
  });
}
