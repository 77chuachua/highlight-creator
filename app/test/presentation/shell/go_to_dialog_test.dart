import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/data/settings_service.dart';
import 'package:highlight_creator/presentation/shell/go_to_dialog.dart';

/// In-memory [SettingsService]: widget tests run inside testWidgets' fake
/// async zone, where real file futures never complete and `await`-ing them
/// deadlocks the test. Keep disk I/O out of these tests entirely.
class _MemorySettingsService extends SettingsService {
  String? gotoBase;

  @override
  Future<String> get language async => 'English';

  @override
  Future<void> setLanguage(String value) async {}

  @override
  Future<String?> get gotoBaseTime async => gotoBase;

  @override
  Future<void> setGotoBaseTime(String value) async => gotoBase = value;
}

/// Widget-level coverage for the Go-to dialog (issues.md: three separate
/// hh/mm/ss inputs per field group): time parsing, base-time persistence,
/// and the returned combined offset.
///
/// Note: the dialog autofocuses its destination field, so `pumpAndSettle`
/// would never settle (cursor-blink timers); we use explicit pumps instead.
void main() {
  testWidgets('three-fields computes dest - base and remembers a changed base',
      (tester) async {
    final svc = _MemorySettingsService();
    final container = ProviderContainer(
      overrides: [settingsServiceProvider.overrideWith((ref) => svc)],
    );
    addTearDown(container.dispose);
    final l10n = container.read(l10nProvider);

    var captured = Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = (await showDialog<Duration?>(
                  context: ctx,
                  builder: (_) => GoToDialog(
                    savedBase: '',
                    settings: svc,
                    l10n: l10n,
                  ),
                ))!;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Destination: 01:30:00
    await tester.enterText(find.byKey(const Key('goto_dest_h')), '01');
    await tester.enterText(find.byKey(const Key('goto_dest_m')), '30');
    await tester.enterText(find.byKey(const Key('goto_dest_s')), '00');
    // Base: 00:10:00
    await tester.enterText(find.byKey(const Key('goto_base_h')), '00');
    await tester.enterText(find.byKey(const Key('goto_base_m')), '10');
    await tester.enterText(find.byKey(const Key('goto_base_s')), '00');
    await tester.tap(find.byKey(const Key('goto_go')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(captured, const Duration(minutes: 80));
    expect(await svc.gotoBaseTime, '00:10:00');
  });

  testWidgets('empty base means offset == dest', (tester) async {
    final svc = _MemorySettingsService();
    final container = ProviderContainer(
      overrides: [settingsServiceProvider.overrideWith((ref) => svc)],
    );
    addTearDown(container.dispose);
    final l10n = container.read(l10nProvider);

    var captured = Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = (await showDialog<Duration?>(
                  context: ctx,
                  builder: (_) => GoToDialog(
                    savedBase: '',
                    settings: svc,
                    l10n: l10n,
                  ),
                ))!;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.enterText(find.byKey(const Key('goto_dest_m')), '10');
    await tester.tap(find.byKey(const Key('goto_go')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(captured, const Duration(minutes: 10));
  });

  testWidgets('base time is prefilled from the remembered value',
      (tester) async {
    final svc = _MemorySettingsService()..gotoBase = '00:05:30';
    final container = ProviderContainer(
      overrides: [settingsServiceProvider.overrideWith((ref) => svc)],
    );
    addTearDown(container.dispose);
    final l10n = container.read(l10nProvider);

    var captured = Duration.zero;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async {
                captured = (await showDialog<Duration?>(
                  context: ctx,
                  builder: (_) => GoToDialog(
                    savedBase: '00:05:30',
                    settings: svc,
                    l10n: l10n,
                  ),
                ))!;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Move the destination to 00:06:00 -> offset is 30s.
    await tester.enterText(find.byKey(const Key('goto_dest_s')), '00');
    await tester.enterText(find.byKey(const Key('goto_dest_m')), '06');
    await tester.tap(find.byKey(const Key('goto_go')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(captured, const Duration(seconds: 30));
  });

  testWidgets('malformed destination shows an error and does not close',
      (tester) async {
    final svc = _MemorySettingsService();
    final container = ProviderContainer(
      overrides: [settingsServiceProvider.overrideWith((ref) => svc)],
    );
    addTearDown(container.dispose);
    final l10n = container.read(l10nProvider);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () {
                showDialog<Duration?>(
                  context: ctx,
                  builder: (_) => GoToDialog(
                    savedBase: '',
                    settings: svc,
                    l10n: l10n,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.enterText(
        find.byKey(const Key('goto_dest_h')), 'not-a-number');
    await tester.tap(find.byKey(const Key('goto_go')));
    await tester.pump();

    expect(find.text(l10n.gotoBadTime), findsOneWidget,
        reason: 'error text stays visible');
    expect(find.byKey(const Key('goto_dialog')), findsOneWidget);
  });

  testWidgets('seconds above 59 are rejected', (tester) async {
    final svc = _MemorySettingsService();
    final container = ProviderContainer(
      overrides: [settingsServiceProvider.overrideWith((ref) => svc)],
    );
    addTearDown(container.dispose);
    final l10n = container.read(l10nProvider);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () {
                showDialog<Duration?>(
                  context: ctx,
                  builder: (_) => GoToDialog(
                    savedBase: '',
                    settings: svc,
                    l10n: l10n,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.enterText(find.byKey(const Key('goto_dest_s')), '61');
    await tester.tap(find.byKey(const Key('goto_go')));
    await tester.pump();

    expect(find.text(l10n.gotoBadTime), findsOneWidget,
        reason: 'error text stays visible');
    expect(find.byKey(const Key('goto_dialog')), findsOneWidget);
  });
}