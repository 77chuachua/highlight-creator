import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/data/settings_service.dart';
import 'package:highlight_creator/presentation/shell/hotkeys.dart';
import 'package:highlight_creator/presentation/shell/settings_screen.dart';

/// Issues.md: settings gains a Hotkeys entry that lists every supported
/// keyboard shortcut.
void main() {
  ProviderContainer container0(SettingsService svc) {
    final container = ProviderContainer(
      overrides: [settingsServiceProvider.overrideWith((ref) => svc)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('hotkeyDefs lists every supported combo', () {
    final l10n = container0(_MemorySettingsService()).read(l10nProvider);
    final combos = hotkeyDefs(l10n).map((e) => e.combo).toList();
    expect(combos, contains('Ctrl + M'));
    expect(combos, contains('Ctrl + G'));
    expect(combos, contains('Ctrl + A'));
    expect(combos, contains('Ctrl + T'));
    expect(combos, contains('Space'));
    expect(combos, contains('Ctrl + \u2190'));
    expect(combos, contains('Ctrl + \u2192'));
    expect(combos.length, greaterThanOrEqualTo(8));
    // Every definition has a non-empty localized label.
    for (final d in hotkeyDefs(l10n)) {
      expect(d.label, isNotEmpty);
      expect(d.combo, isNotEmpty);
    }
  });

  testWidgets('settings shows a Hotkeys tile that opens the shortcut list',
      (tester) async {
    final svc = _MemorySettingsService();
    final container = container0(svc);
    final l10n = container.read(l10nProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: SettingsScreen())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text(l10n.hotkeyTitle), findsOneWidget);
    await tester.tap(find.text(l10n.hotkeyTitle));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('hotkeys_dialog')), findsOneWidget);
    for (final d in hotkeyDefs(l10n)) {
      expect(find.text(d.combo), findsOneWidget,
          reason: 'combo ${d.combo} should be listed');
    }
  });
}

/// In-memory [SettingsService]: widget tests run inside testWidgets' fake
/// async zone, where real file futures never complete and `await`-ing them
/// deadlocks the test. Keep disk I/O out of these tests entirely.
class _MemorySettingsService extends SettingsService {
  @override
  Future<String> get language async => 'English';

  @override
  Future<void> setLanguage(String value) async {}

  @override
  Future<String?> get gotoBaseTime async => null;

  @override
  Future<void> setGotoBaseTime(String value) async {}
}
