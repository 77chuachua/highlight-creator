import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/font_name.dart';

void main() {
  test('readFontFamily returns a real name for an installed font', () {
    const path = r'C:\Windows\Fonts\arial.ttf';
    if (!File(path).existsSync()) {
      markTestSkipped('System font missing on this machine');
      return;
    }
    final name = readFontFamily(path);
    expect(name, isNotNull, reason: 'should parse Arial name table');
    expect(name!.toLowerCase(), contains('arial'));
  });

  test('readFontFamily returns null for a missing file', () {
    expect(readFontFamily(r'C:\nonexistent\font.ttf'), isNull);
  });

  test('readFontFamily returns null for garbage bytes', () {
    final tmp = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}bad_font.ttf');
    tmp.writeAsStringSync('this is not a font file at all');
    addTearDown(() => tmp.deleteSync());
    expect(readFontFamily(tmp.path), isNull);
  });

  test('fontHasGlyphs: CJK-capable font covers CJK, Latin-only does not',
      () async {
    final cjk = [
      r'C:\Windows\Fonts\msyh.ttc',
      r'C:\Windows\Fonts\simhei.ttf',
      r'C:\Windows\Fonts\simsun.ttc',
    ].firstWhere((f) => File(f).existsSync(), orElse: () => '');
    final latin = [
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\arial.ttf',
    ].firstWhere((f) => File(f).existsSync(), orElse: () => '');
    if (cjk.isEmpty || latin.isEmpty) {
      markTestSkipped('System fonts missing on this machine');
      return;
    }

    const haveCjk = [0x7CBE, 0x8FDB, 0x96C6, 0x9526]; // 精彩进球集锦
    const latinOnly = [0x41, 0x42, 0x43]; // ABC — every font covers Latin

    expect(fontHasGlyphs(cjk, haveCjk), isTrue,
        reason: 'a CJK-capable font must cover Chinese ideographs');
    expect(fontHasGlyphs(latin, haveCjk), isFalse,
        reason: 'a Latin-only font must NOT claim Chinese ideographs '
            '(this is what triggers the tofu substitution)');
    expect(fontHasGlyphs(latin, latinOnly), isTrue,
        reason: 'a Latin-only font still covers Latin codepoints');
  });

  test('fontHasGlyphs fails safe on garbage / missing files', () {
    expect(fontHasGlyphs(r'C:\nonexistent\font.ttf', const [0x41]), isFalse);
    final tmp = File('${Directory.systemTemp.path}${Platform.pathSeparator}'
        'bad_font2.ttf');
    tmp.writeAsStringSync('this is not a font file at all');
    addTearDown(() => tmp.deleteSync());
    expect(fontHasGlyphs(tmp.path, const [0x41]), isFalse);
  });
}