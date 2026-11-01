import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/services/template_generator_service.dart';

/// Picking a startup is supposed to drag its pack's transition and ending along
/// (SelectedTemplatesNotifier.selectStartupWithSet). That only works when the
/// three files of one pack resolve to the SAME set key, and the registry is full
/// of packs this build never shipped: the legacy blue/yellow sets, downloaded
/// online sets cached as `plugin_<id>_<rev>.mp4`, imported `myPack_startup.mp4`.
void main() {
  group('setOfPath keeps the shipped sets matched by exact file name', () {
    test('green ending differs from its startup file name', () {
      expect(TemplateGeneratorService.setOfPath('C:\\t\\startup_green.mp4')?.id,
          'green');
      expect(
          TemplateGeneratorService.setOfPath('C:\\t\\ending_green_theme.mp4')
              ?.id,
          'green');
    });

    test('nocturne', () {
      expect(TemplateGeneratorService.setOfPath('C:\\t\\transition_nocturne.mp4')?.id,
          'nocturne');
    });

    test('an online set is not a built-in set', () {
      expect(
          TemplateGeneratorService.setOfPath(
              'C:\\t\\plugins\\plugin_aurora-startup_5b54af6752e8.mp4'),
          isNull);
    });
  });

  group('setKeyOfPath', () {
    test('legacy blue pack: every file maps to "blue"', () {
      for (final name in [
        'startup_blue.mp4',
        'transition_blue.mp4',
        'ending_blue.mp4',
      ]) {
        expect(TemplateGeneratorService.setKeyOfPath('C:\\t\\$name'), 'blue',
            reason: name);
      }
    });

    test('legacy yellow pack', () {
      expect(TemplateGeneratorService.setKeyOfPath('C:\\t\\startup_yellow.mp4'),
          'yellow');
      expect(
          TemplateGeneratorService.setKeyOfPath('C:\\t\\ending_yellow.mp4'),
          'yellow');
    });

    test('shipped sets keep their set id', () {
      expect(TemplateGeneratorService.setKeyOfPath('C:\\t\\startup_green.mp4'),
          'green');
      expect(
          TemplateGeneratorService.setKeyOfPath(
              'C:\\t\\ending_green_theme.mp4'),
          'green');
    });

    test('downloaded online set: plugin prefix and revision are stripped', () {
      expect(
          TemplateGeneratorService.setKeyOfPath(
              'C:\\t\\plugins\\plugin_aurora-startup_5b54af6752e8.mp4'),
          'aurora');
      expect(
          TemplateGeneratorService.setKeyOfPath(
              'C:\\t\\plugins\\plugin_aurora-ending_866e0cd5f170.mp4'),
          'aurora');
      expect(
          TemplateGeneratorService.setKeyOfPath(
              'C:\\t\\plugins\\plugin_zenith-transition_58b030b99bd5.mp4'),
          'zenith');
      // The revision is author-controlled, not always a sha prefix.
      expect(
          TemplateGeneratorService.setKeyOfPath(
              'C:\\t\\plugins\\plugin_aurora-ending_1.mp4'),
          'aurora');
    });

    test('separators are interchangeable', () {
      expect(
          TemplateGeneratorService.setKeyOfPath(
              'C:/t/plugins/plugin_zenith-ending_6aaab1e6ca65.mp4'),
          'zenith');
      expect(TemplateGeneratorService.setKeyOfPath('C:\\t\\startup_zenith.mp4'),
          'zenith');
    });

    test('names without a type word carry no set', () {
      expect(TemplateGeneratorService.setKeyOfPath(''), isNull);
      expect(TemplateGeneratorService.setKeyOfPath('C:\\t\\bg_music.mp3'),
          isNull);
      expect(TemplateGeneratorService.setKeyOfPath('C:\\t\\startup.mp4'), isNull);
    });
  });
}
