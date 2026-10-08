// Beginner guide dialog behavior: pagination, swipe, don't-show checkbox,
// and the auto-popup on app startup. Pure widget tests — no ffmpeg needed.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/database/database.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/data/settings_service.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/main.dart';
import 'package:highlight_creator/presentation/shell/guide_dialog.dart';

class _MemorySettingsService extends SettingsService {
  _MemorySettingsService({required this.lang, this.autoShow = true});

  final String lang;
  bool autoShow;

  @override
  Future<String> get language async => lang;

  @override
  Future<void> setLanguage(String value) async {}

  @override
  Future<bool> get guideAutoShow async => autoShow;

  @override
  Future<void> setGuideAutoShow(bool value) async => autoShow = value;
}

/// Host that opens the GuideDialog in a real dialog route.
class _GuideHost extends ConsumerStatefulWidget {
  const _GuideHost();

  @override
  ConsumerState<_GuideHost> createState() => _GuideHostState();
}

class _GuideHostState extends ConsumerState<_GuideHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(context: context, builder: (_) => const GuideDialog());
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}

Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  var attempts = 0;
  while (!tester.any(finder) && attempts++ < 200) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(tester.any(finder), isTrue, reason: '$finder never appeared');
}

void main() {
  setUpAll(() async {
    if (!locator.isRegistered<AppDatabase>()) {
      await initializeDependenciesFallback();
    }
  });

  Future<ProviderContainer> makeContainer(SettingsService svc) async {
    final container = ProviderContainer(overrides: [
      settingsServiceProvider.overrideWithValue(svc),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('guide dialog: 8 pages via next/prev/swipe, closes on done',
      (tester) async {
    final svc = _MemorySettingsService(lang: '中文');
    final container = await makeContainer(svc);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: _GuideHost()),
    ));
    await tester.pumpAndSettle();

    final l10n = container.read(l10nProvider);
    expect(find.byKey(const Key('guide_dialog')), findsOneWidget);
    expect(find.text(l10n.guideStep1), findsOneWidget);
    expect(find.text('1 / 8'), findsOneWidget);

    await tester.tap(find.byKey(const Key('guide_next')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.guideStep2), findsOneWidget);

    await tester.tap(find.byKey(const Key('guide_prev')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.guideStep1), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(find.text(l10n.guideStep2), findsOneWidget);

    for (var i = 2; i < 8; i++) {
      await tester.tap(find.byKey(const Key('guide_next')));
      await tester.pumpAndSettle();
    }
    expect(find.text(l10n.guideStep8), findsOneWidget);

    await tester.tap(find.byKey(const Key('guide_next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('guide_dialog')), findsNothing);
  });

  testWidgets('guide dialog: don\'t-show checkbox persists the setting',
      (tester) async {
    final svc = _MemorySettingsService(lang: '中文');
    final container = await makeContainer(svc);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: _GuideHost()),
    ));
    await tester.pumpAndSettle();

    final checkbox = tester
        .widget<CheckboxListTile>(find.byKey(const Key('guide_checkbox')));
    expect(checkbox.value, isFalse); // auto-show enabled -> unchecked

    await tester.tap(find.byKey(const Key('guide_checkbox')));
    await tester.pumpAndSettle();
    expect(await svc.guideAutoShow, isFalse);

    await tester.tap(find.byKey(const Key('guide_checkbox')));
    await tester.pumpAndSettle();
    expect(await svc.guideAutoShow, isTrue);
  });

  /// Real desktop window size — the default 800x600 test surface is too
  /// narrow for the main window layout.
  void useDesktopSize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('guide auto-popups on startup when enabled', (tester) async {
    useDesktopSize(tester);
    final svc = _MemorySettingsService(lang: 'English', autoShow: true);
    final container = await makeContainer(svc);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const HighlightCreatorApp(),
    ));
    await pumpUntilFound(tester, find.byKey(const Key('guide_dialog')));
    expect(find.byKey(const Key('guide_dialog')), findsOneWidget);
  });

  testWidgets('guide does not popup on startup when disabled',
      (tester) async {
    useDesktopSize(tester);
    final svc = _MemorySettingsService(lang: 'English', autoShow: false);
    final container = await makeContainer(svc);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const HighlightCreatorApp(),
    ));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('guide_dialog')), findsNothing);
  });

  testWidgets(
      'guide honors persisted opt-out on startup (real file-backed settings)',
      (tester) async {
    useDesktopSize(tester);
    final tempDir = Directory.systemTemp.createTempSync('hc_guide_test_');
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final settingsFile =
        File('${tempDir.path}${Platform.pathSeparator}settings.json');
    settingsFile.writeAsStringSync(jsonEncode({'guideAutoShow': false}));

    // Real SettingsService against a temp file: reproduces the production
    // startup sequence where the language load is still reading the file
    // when the post-frame guide check fires.
    final svc = SettingsService(path: settingsFile.path);
    final container = await makeContainer(svc);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const HighlightCreatorApp(),
    ));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('guide_dialog')), findsNothing);
  });
}
