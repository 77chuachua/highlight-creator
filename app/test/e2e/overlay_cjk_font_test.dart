import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';

/// Regression for "preview text does not support Chinese — tofu in the
/// video": when the overlay text needs CJK glyphs, a font that lacks those
/// glyphs (the Latin-only presets like Segoe UI, dead paths, or user-browsed
/// custom fonts under any filename) must be substituted with the default
/// CJK-capable system font. Dead font paths must also fall back instead of
/// breaking the whole drawtext filter.
void main() {
  late String projectRoot;
  late VideoProcessingService service;
  late String ffmpeg;

  setUpAll(() async {
    projectRoot = _resolveProjectRoot();
    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    ffmpeg = ffmpegPath ?? '';
    service = VideoProcessingService(ffmpegPath: ffmpegPath);
    VideoProcessingService.commandLogPath = '$projectRoot\\ffmpeg_command';
    VideoProcessingService.commandLogContext =
        'overlay_cjk_font_test.dart :: CJK font fallback';
  });

  test('Chinese text with a Latin-only preset font renders CJK glyphs, '
      'not tofu', () async {
    final dir = '$projectRoot\\temp\\e2e\\cjk_font';
    Directory(dir).createSync(recursive: true);
    final base = '$projectRoot\\test\\e2e\\videoSource\\startup.mp4';
    expect(File(base).existsSync(), isTrue, reason: 'fixture missing: $base');

    final latin = [
      r'C:\Windows\Fonts\segoeui.ttf',
      r'C:\Windows\Fonts\consola.ttf',
      r'C:\Windows\Fonts\arial.ttf',
    ].firstWhere((f) => File(f).existsSync(), orElse: () => '');
    expect(latin, isNotEmpty, reason: 'no Latin-only test font on this machine');

    Future<List<int>> render(String name, String text, String? font) async {
      final out = '$dir\\$name.mp4';
      final res = await service.overlayText(
        inputPath: base,
        outputPath: out,
        text: text,
        fontPath: font,
        fontSize: 64,
        fontColor: '#F5C42D',
      );
      expect(res.exitCode, 0, reason: 'ffmpeg failed:\n${res.stderr}');
      return _firstFramePng(ffmpeg, out, dir, name);
    }

    // 1) CJK text + Latin-only font must match the default system font's
    //    render byte-for-byte — the Latin font was substituted away, so the
    //    Chinese characters are real glyphs, not tofu boxes.
    const zh = '精彩进球集锦';
    final latinZhPng = await render('latin_zh', zh, latin);
    final defaultZhPng = await render('default_zh', zh, null);
    expect(latinZhPng, equals(defaultZhPng),
        reason: 'CJK text with a Latin-only font rendered differently from '
            'the default font — the CJK substitution did not kick in');

    // 2) Latin text keeps the user-selected font (no over-substitution):
    //    it must differ from the default font's render.
    final latinEnPng = await render('latin_en', 'ABC', latin);
    final defaultEnPng = await render('default_en', 'ABC', null);
    expect(latinEnPng, isNot(equals(defaultEnPng)),
        reason: 'Latin text should keep the user-selected font');

    // 3) A dead font path falls back to the system font instead of failing.
    final deadZhPng = await render('dead_zh', zh, r'C:\nonexistent\font.ttf');
    expect(deadZhPng, equals(defaultZhPng),
        reason: 'dead font path should render with the system font');

    // 4) A user-BROWSED Latin-only font (renamed so no filename list can
    //    catch it) must still be substituted for CJK text. This is the
    //    4th-time regression: the old hardcoded Latin-only filename list
    //    trusted browsed custom fonts as-is, so Chinese rendered as tofu.
    //    Coverage is decided by the font's cmap table, not its filename.
    final browsedLatin = '$dir\\browsed_latin_font.ttf';
    File(latin).copySync(browsedLatin);
    final browsedLatinZhPng = await render('browsed_latin_zh', zh, browsedLatin);
    expect(browsedLatinZhPng, equals(defaultZhPng),
        reason: 'a user-browsed Latin-only font must be substituted for CJK '
            'text (cmap coverage, not filename, must decide)');

    // 5) A user-browsed font that DOES carry CJK glyphs is kept (no
    //    over-substitution): its render must differ from the default font.
    final cjkSource = [
      r'C:\Windows\Fonts\msyh.ttc',
      r'C:\Windows\Fonts\msyhbd.ttc',
      r'C:\Windows\Fonts\simhei.ttf',
    ].firstWhere((f) => File(f).existsSync(), orElse: () => '');
    expect(cjkSource, isNotEmpty,
        reason: 'no CJK-capable test font on this machine');
    final browsedCjk = '$dir\\browsed_cjk_font.ttc';
    File(cjkSource).copySync(browsedCjk);
    final browsedCjkZhPng = await render('browsed_cjk_zh', zh, browsedCjk);
    expect(browsedCjkZhPng, isNot(equals(defaultZhPng)),
        reason: 'a custom CJK-capable font should be kept, not substituted');
  });
}

/// Extract frame 1 of [mp4] as PNG bytes — deterministic for identical
/// pixels, so byte equality proves identical rendered glyphs.
List<int> _firstFramePng(String ffmpeg, String mp4, String dir, String name) {
  final png = '$dir\\$name.png';
  final res = Process.runSync(
      ffmpeg, ['-y', '-i', mp4, '-frames:v', '1', '-update', '1', png]);
  expect(res.exitCode, 0, reason: 'frame extract failed: ${res.stderr}');
  return File(png).readAsBytesSync();
}

String _resolveProjectRoot() {
  var dir = Directory.current;
  while (true) {
    if (File('${dir.path}\\AGENTS.md').existsSync() ||
        Directory('${dir.path}\\app').existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return Directory.current.path;
}
