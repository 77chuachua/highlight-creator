import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/repositories/template_repository_impl.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/template.dart';

/// Verify bg_music.mp3 (shipped beside ffmpeg) is registered as an embedded
/// background music template at startup.
void main() {
  test('registerEmbeddedBgm adds bg_music.mp3 next to ffmpeg (idempotent)',
      () async {
    final temp = Directory.systemTemp.createTempSync('hl_bgm_reg');
    try {
      File('${temp.path}\\bg_music.mp3').writeAsBytesSync([1, 2, 3]);
      final repo = TemplateRepositoryImpl(
          storagePath: '${temp.path}\\templates.json');

      await registerEmbeddedBgm(
          repo: repo, ffmpegPath: '${temp.path}\\ffmpeg.exe');
      final bgms = await repo.listByType(TemplateType.backgroundMusic);
      expect(bgms.length, 1);
      expect(bgms.first.path, '${temp.path}\\bg_music.mp3');
      expect(bgms.first.name, 'bg_music.mp3');

      // Second call must not duplicate the entry.
      await registerEmbeddedBgm(
          repo: repo, ffmpegPath: '${temp.path}\\ffmpeg.exe');
      expect((await repo.listByType(TemplateType.backgroundMusic)).length, 1);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });

  test('registerEmbeddedBgm is a no-op when bg_music.mp3 is missing', () async {
    final temp = Directory.systemTemp.createTempSync('hl_bgm_reg2');
    try {
      final repo = TemplateRepositoryImpl(
          storagePath: '${temp.path}\\templates.json');
      await registerEmbeddedBgm(
          repo: repo, ffmpegPath: '${temp.path}\\ffmpeg.exe');
      expect(await repo.listByType(TemplateType.backgroundMusic), isEmpty);
    } finally {
      temp.deleteSync(recursive: true);
    }
  });
}
