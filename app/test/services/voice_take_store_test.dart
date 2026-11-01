import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/services/voice_take_store.dart';

void main() {
  final sep = Platform.pathSeparator;
  late Directory root;
  late VoiceTakeStore takes;
  late String takeDir;

  setUp(() {
    root = Directory.systemTemp.createTempSync('voice_takes_');
    takeDir = '${root.path}${sep}takes';
    takes = VoiceTakeStore(takeDir);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  /// A stand-in for one clone: same size, different first byte per [flavour].
  String clone(String name, int flavour, {int bytes = 4096}) {
    final file = File('${root.path}${sep}$name');
    file.writeAsBytesSync([flavour, ...List<int>.filled(bytes - 1, 0)]);
    return file.path;
  }

  String signature([String text = '老庄这脚球太漂亮了']) =>
      VoiceTakeStore.signature(
        packId: 'pack-1',
        text: text,
        speed: 1,
        instruct: '',
        promptText: '这是我的声音',
      );

  test('a kept take comes back for the same line, with its seed', () {
    final audio = clone('preview_1.wav', 1);

    takes.keep('slot-1', signature(), audio, seed: 123456789);
    final found = takes.find('slot-1', signature());

    expect(found, isNotNull);
    expect(File(found!.path).readAsBytesSync().first, 1);
    expect(File(found.path).parent.path, takeDir);
    expect(found.seed, 123456789);
  });

  test('an edited line invalidates the take', () {
    takes.keep('slot-1', signature(), clone('preview_1.wav', 1));

    expect(takes.find('slot-1', signature('换了一句解说')), isNull);
  });

  test('a re-recorded voice pack invalidates the take', () {
    // The pack id survives a re-record, so the audio identity is what changes.
    String withVoice(String voice) => VoiceTakeStore.signature(
          packId: 'pack-1',
          text: '老庄这脚球太漂亮了',
          voice: voice,
        );
    takes.keep('slot-1', withVoice('4096:1'), clone('preview_1.wav', 1));

    expect(takes.find('slot-1', withVoice('4096:2')), isNull);
    expect(takes.find('slot-1', withVoice('4096:1')), isNotNull);
  });

  test('the next audition replaces the previous take and its seed', () {
    takes.keep('slot-1', signature(), clone('first.wav', 1), seed: 42);
    takes.keep('slot-1', signature(), clone('second.wav', 2), seed: 777);

    final found = takes.find('slot-1', signature());
    expect(found, isNotNull);
    expect(File(found!.path).readAsBytesSync().first, 2,
        reason: 'the take that was heard last is the one the render uses');
    expect(found.seed, 777);
    expect(
        Directory(takeDir)
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.tmp')),
        isEmpty);
  });

  test('a mark written before seeds is still readable, without a seed', () {
    takes.keep('slot-1', signature(), clone('preview_1.wav', 1));
    // Simulate the older format: the plain signature, no JSON.
    final mark = File('${takeDir}${sep}slot-1.sig')
      ..writeAsStringSync(signature());

    final found = takes.find('slot-1', signature());
    expect(found, isNotNull);
    expect(found!.seed, isNull);
  });

  test('a mark that is neither JSON nor the signature is ignored', () {
    takes.keep('slot-1', signature(), clone('preview_1.wav', 1));
    File('${takeDir}${sep}slot-1.sig').writeAsStringSync('{"signature":"x","seed":1}');
    expect(takes.find('slot-1', signature()), isNull);

    File('${takeDir}${sep}slot-1.sig').writeAsStringSync('garbage');
    expect(takes.find('slot-1', signature()), isNull);
  });

  test('a stub audio file is never a take', () {
    final stub = File('${root.path}${sep}stub.wav')
      ..writeAsBytesSync(List<int>.filled(64, 0));
    takes.keep('slot-1', signature(), stub.path);

    expect(takes.find('slot-1', signature()), isNull);
  });

  test('a slot id with path characters stays inside the store', () {
    final id = 'a/b\\c:1';
    takes.keep(id, signature(), clone('preview_odd.wav', 3), seed: 5);

    final found = takes.find(id, signature());
    expect(found, isNotNull);
    expect(File(found!.path).parent.path, takeDir);
    expect(Directory('${takeDir}${sep}a').existsSync(), isFalse);
    // The mark is JSON, not the id itself.
    final raw = File('${takeDir}${sep}a_b_c_1.sig').readAsStringSync();
    expect(jsonDecode(raw), isA<Map>());
  });

  test('an unknown slot has no take', () {
    expect(takes.find('never-auditioned', signature()), isNull);
  });
}
