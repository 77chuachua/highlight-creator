import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/repositories/template_repository_impl.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/presentation/shell/template_editor_dialog.dart';
import 'package:highlight_creator/services/template_plugin_service.dart';

/// Reproduces the "template config dialog" layout exception: opening it threw
/// `RenderBox was not laid out` → the frame loop kept throwing and the UI
/// froze. The dialog must lay out cleanly at desktop sizes.
void main() {
  // The dialog fetches the plugin catalogue on open. Point it at a closed port
  // so these layout tests stay hermetic and fast instead of reaching for the
  // real GitHub URL — and so they also exercise the offline path.
  setUpAll(() {
    TemplatePluginService.manifestUrl =
        'http://127.0.0.1:1/manifest.json';
  });

  Future<void> openDialog(WidgetTester tester, Size size) async {
    final tmp = Directory.systemTemp.createTempSync('hl_tpl_dialog_');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          templateRepositoryProvider.overrideWith(
            (ref) => TemplateRepositoryImpl(
              storagePath: '${tmp.path}${Platform.pathSeparator}templates.json',
            ),
          ),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: ctx,
                  builder: (_) => const TemplateEditorDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump();
    // Let the 800ms "save title" debounce fire so no timer is left pending
    // when the widget tree is torn down.
    await tester.pump(const Duration(milliseconds: 900));
  }

  testWidgets('opens and lays out at 1280x800 without rendering exceptions',
      (tester) async {
    await openDialog(tester, const Size(1280, 800));
    expect(tester.takeException(), isNull);
    expect(find.byType(TemplateEditorDialog), findsOneWidget);
  });

  testWidgets('opens and lays out at 1024x640 without rendering exceptions',
      (tester) async {
    await openDialog(tester, const Size(1024, 640));
    expect(tester.takeException(), isNull);
    expect(find.byType(TemplateEditorDialog), findsOneWidget);
  });

  testWidgets('switching template cards does not throw (issues.md)',
      (tester) async {
    await openDialog(tester, const Size(1280, 800));

    // Default selection is the first startup card ("Blue"); switch to another
    // startup template. Regression: the dialog reused one media_kit Player and
    // the preview did not re-render after the switch.
    expect(find.text('Yellow'), findsWidgets);
    await tester.tap(find.text('Yellow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(TemplateEditorDialog), findsOneWidget);

    // Let the save-title debounce fire so no timer is left pending.
    await tester.pump(const Duration(milliseconds: 900));
  });
}
