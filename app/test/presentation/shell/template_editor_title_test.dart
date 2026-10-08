import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/presentation/shell/template_editor_dialog.dart';

/// Regression for the "preview text leaks across tabs" bug: the template
/// config dialog shares one preview-text field across the startup /
/// transition / ending tabs. When the dialog was opened on the ending tab
/// (whose template had a saved title) and the user switched to a tab whose
/// selected template had no saved title, the field kept showing the ending
/// title. The field must always resolve to the new entry's own text.
void main() {
  const fallback = 'Awesome Highlight';

  Template t({String? title, TemplateType type = TemplateType.startup}) =>
      Template(
        id: 'id-${title ?? 'none'}-${type.name}',
        name: 'tpl',
        path: r'C:\videos\tpl.mp4',
        type: type,
        title: title,
      );

  group('resolvePreviewText', () {
    test('returns the saved title when present', () {
      expect(
        TemplateEditorDialog.resolvePreviewText(t(title: 'Double check'),
            fallback),
        'Double check',
      );
    });

    test('falls back to the placeholder when the title is null', () {
      // The bug: switching from ending ("Double check") to a startup
      // template without a title must NOT keep showing "Double check".
      expect(TemplateEditorDialog.resolvePreviewText(t(), fallback), fallback);
    });

    test('falls back to the placeholder when the title is empty', () {
      expect(
        TemplateEditorDialog.resolvePreviewText(t(title: ''), fallback),
        fallback,
      );
    });

    test('falls back when there is no template at all', () {
      expect(TemplateEditorDialog.resolvePreviewText(null, fallback), fallback);
    });

    test('per-category titles never leak: each tab resolves its own text', () {
      final ending = t(title: 'Double check', type: TemplateType.ending);
      final startup = t(type: TemplateType.startup);
      final transition = t(type: TemplateType.transition);

      final endingText =
          TemplateEditorDialog.resolvePreviewText(ending, fallback);
      final startupText =
          TemplateEditorDialog.resolvePreviewText(startup, fallback);
      final transitionText =
          TemplateEditorDialog.resolvePreviewText(transition, fallback);

      expect(endingText, 'Double check');
      expect(startupText, isNot('Double check'));
      expect(transitionText, isNot('Double check'));
      expect(startupText, fallback);
      expect(transitionText, fallback);
    });
  });

  test('defaultStartupTitle is localized', () {
    expect(TemplateEditorDialog.defaultStartupTitle('中文'), '精彩集锦');
    expect(
        TemplateEditorDialog.defaultStartupTitle('English'), 'Awesome Highlight');
  });
}
