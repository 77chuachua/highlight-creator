import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/presentation/shell/template_editor_dialog.dart';

/// Verify embedded startup templates apply the localized placeholder as the
/// default title.
void main() {
  test('default startup title is the localized placeholder', () {
    expect(TemplateEditorDialog.defaultStartupTitle('中文'), '精彩集锦');
    expect(
        TemplateEditorDialog.defaultStartupTitle('English'), 'Awesome Highlight');
  });

  test('default startup title is not the old preview default', () {
    expect(TemplateEditorDialog.defaultStartupTitle('中文'),
        isNot('精彩进球集锦'));
  });
}
