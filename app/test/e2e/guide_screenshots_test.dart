// Automatically generates the annotated beginner-guide screenshots into
// app\windows\res (bundled as Flutter assets, shown by GuideDialog).
//
// For each guide step the real MainWindow is pumped with a fake player and
// in-memory settings, captured via a RepaintBoundary, annotated with red
// boxes/arrows around the focus widgets and written as PNG — once for the
// Chinese UI and once for the English UI.
//
// Run with:  flutter test test/e2e/guide_screenshots_test.dart

import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/database/database.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/data/settings_service.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/main.dart';
import 'package:highlight_creator/presentation/player/player_state.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/presentation/shell/template_panel.dart';

const _screen = Size(1280, 720);
const _red = Color(0xFFFF1744);
const _scale = 2.0; // render at 2x so the guide images stay crisp

enum _ArrowDir { ne, nw, w }

class _MemorySettingsService extends SettingsService {
  _MemorySettingsService({required this.lang});

  final String lang;
  bool autoShow = false; // keep the guide closed while shooting

  @override
  Future<String> get language async => lang;

  @override
  Future<void> setLanguage(String value) async {}

  @override
  Future<bool> get guideAutoShow async => autoShow;

  @override
  Future<void> setGuideAutoShow(bool value) async => autoShow = value;
}

/// Player view-model fake: video loaded + playing, no media_kit natives.
class _FakePlayerViewModel extends VideoPlayerViewModel {
  @override
  VideoPlayerState build() => const VideoPlayerState(
        status: PlayerStatus.playing,
        videoPath: r'C:\Videos\test1.mp4',
        position: Duration(seconds: 42),
        duration: Duration(minutes: 5),
      );

  @override
  Future<void> play() async =>
      state = state.copyWith(status: PlayerStatus.playing);

  @override
  Future<void> pause() async =>
      state = state.copyWith(status: PlayerStatus.paused);

  @override
  Future<void> stop() async {}

  @override
  Future<void> loadVideo(String path, {Duration? initialPosition}) async {}
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

String? _findMaterialIconsFont() {
  // flutter test runs <flutter>\bin\cache\artifacts\engine\...\flutter_tester.exe
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 6; i++) {
    final candidate = File(
        '${dir.path}\\bin\\cache\\artifacts\\material_fonts\\materialicons-regular.otf');
    if (candidate.existsSync()) return candidate.path;
    dir = dir.parent;
  }
  return null;
}

/// Register real fonts: widget tests default to Ahem, which renders Chinese
/// text and icons as boxes — useless for screenshots.
Future<void> _loadFonts() async {
  final sources = <String, String>{
    'Roboto': r'C:\Windows\Fonts\simhei.ttf',
    'monospace': r'C:\Windows\Fonts\simhei.ttf',
  };
  final icons = _findMaterialIconsFont();
  if (icons != null) sources['MaterialIcons'] = icons;

  for (final entry in sources.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) continue;
    final bytes = await file.readAsBytes();
    final loader = FontLoader(entry.key)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

Future<ProviderContainer> _pumpApp(WidgetTester tester,
    {required String lang}) async {
  tester.view.physicalSize = _screen;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(overrides: [
    settingsServiceProvider
        .overrideWithValue(_MemorySettingsService(lang: lang)),
    videoPlayerProvider.overrideWith(_FakePlayerViewModel.new),
  ]);
  addTearDown(container.dispose);

  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('capture_root'),
      child: UncontrolledProviderScope(
        container: container,
        child: const HighlightCreatorApp(),
      ),
    ),
  );

  // Wait until the language is applied and the default project exists.
  var attempts = 0;
  while (container.read(languageProvider) != lang ||
      container.read(recordProvider).selectedProjectId == null) {
    if (attempts++ > 300) fail('app did not settle');
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
  return container;
}

Future<void> _ensureVisible(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.4);
  await tester.pumpAndSettle();
}

Rect _scaled(Rect r, double s) =>
    Rect.fromLTRB(r.left * s, r.top * s, r.right * s, r.bottom * s);

Rect _unionRect(WidgetTester tester, Finder finder) {
  final n = tester.widgetList(finder).length;
  Rect? acc;
  for (var i = 0; i < n; i++) {
    final r = tester.getRect(finder.at(i));
    acc = acc == null ? r : acc.expandToInclude(r);
  }
  return acc ?? Rect.zero;
}

void _drawArrow(Canvas canvas, Rect target, _ArrowDir dir) {
  final fill = Paint()..color = _red;
  final stroke = Paint()
    ..color = _red
    ..style = PaintingStyle.stroke
    ..strokeWidth = 3 * _scale;
  const s = 70 * _scale;
  final (from, to) = switch (dir) {
    _ArrowDir.ne => (
        target.topRight + const Offset(s, -0.7 * s),
        target.topRight + const Offset(8 * _scale, -6 * _scale)
      ),
    _ArrowDir.nw => (
        target.topLeft + const Offset(-s, -0.7 * s),
        target.topLeft + const Offset(-8 * _scale, -6 * _scale)
      ),
    _ArrowDir.w => (
        target.centerLeft + const Offset(-s, 0),
        target.centerLeft + const Offset(-6 * _scale, 0)
      ),
  };
  canvas.drawLine(from, to, stroke);
  final delta = to - from;
  final du = delta / delta.distance;
  final n = Offset(-du.dy, du.dx);
  const head = 14 * _scale;
  canvas.drawPath(
    Path()
      ..moveTo(to.dx, to.dy)
      ..lineTo((to - du * head + n * head * 0.5).dx,
          (to - du * head + n * head * 0.5).dy)
      ..lineTo((to - du * head - n * head * 0.5).dx,
          (to - du * head - n * head * 0.5).dy)
      ..close(),
    fill,
  );
}

/// Capture the current frame, annotate it and write a PNG to windows\res.
Future<void> _capture(
  WidgetTester tester, {
  required String fileName,
  List<Finder> boxes = const [],
  List<(Finder, _ArrowDir)> arrows = const [],
  List<Rect> extraBoxes = const [],
  Rect Function(Size screen)? cropOf,
}) async {
  final boundaryFinder = find.byKey(const Key('capture_root'));
  final screen = tester.getSize(boundaryFinder);
  final crop = cropOf?.call(screen) ?? Offset.zero & screen;
  final boxRects = [for (final f in boxes) tester.getRect(f), ...extraBoxes];
  final arrowSpecs = [for (final (f, d) in arrows) (tester.getRect(f), d)];
  await tester.pump();

  final written = await tester.runAsync<int>(() async {
    final boundary =
        tester.renderObject(boundaryFinder) as RenderRepaintBoundary;
    final full = await boundary.toImage(pixelRatio: _scale);

    final src = Rect.fromLTWH(crop.left * _scale, crop.top * _scale,
        crop.width * _scale, crop.height * _scale);
    final outW = (crop.width * _scale).round();
    final outH = (crop.height * _scale).round();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
        full, src, Rect.fromLTWH(0, 0, outW.toDouble(), outH.toDouble()),
        Paint());

    final stroke = Paint()
      ..color = _red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * _scale;
    for (final r in boxRects) {
      final sr = _scaled(r.shift(-crop.topLeft), _scale).inflate(6 * _scale);
      canvas.drawRRect(
          RRect.fromRectAndRadius(sr, const Radius.circular(6 * _scale)), stroke);
    }
    for (final (r, dir) in arrowSpecs) {
      _drawArrow(canvas, _scaled(r.shift(-crop.topLeft), _scale), dir);
    }

    final picture = recorder.endRecording();
    final annotated = await picture.toImage(outW, outH);
    final bytes =
        await annotated.toByteData(format: ui.ImageByteFormat.png);

    final out = File('${_resolveProjectRoot()}\\app\\windows\\res\\$fileName');
    out.createSync(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    return out.lengthSync();
  });

  expect(written, greaterThan(1000), reason: '$fileName too small');
}

Finder _templatePanel(TemplateType type) => find.byWidgetPredicate(
    (w) => w is TemplatePanel && w.type == type);

void main() {
  setUpAll(() async {
    await _loadFonts();
    if (!locator.isRegistered<AppDatabase>()) {
      await initializeDependenciesFallback();
    }
  });

  for (final lang in const ['中文', 'English']) {
    final code = lang == '中文' ? 'zh' : 'en';
    String out(String step) => 'guide_${code}_$step.png';

    testWidgets('guide[$code] 01 add source files', (tester) async {
      await _pumpApp(tester, lang: lang);
      await _capture(tester,
          fileName: out('01'),
          boxes: [find.byKey(const Key('source_add_button'))],
          arrows: [(find.byKey(const Key('source_add_button')), _ArrowDir.w)],
          cropOf: (_) => const Rect.fromLTWH(900, 0, 380, 330));
    });

    testWidgets('guide[$code] 02 mark button during playback',
        (tester) async {
      await _pumpApp(tester, lang: lang);
      await _capture(tester,
          fileName: out('02'),
          boxes: [find.byKey(const Key('mark_button'))],
          arrows: [(find.byKey(const Key('mark_button')), _ArrowDir.ne)],
          cropOf: (_) => const Rect.fromLTWH(0, 300, 980, 200));
    });

    testWidgets('guide[$code] 03 mark dialog description + zoom',
        (tester) async {
      await _pumpApp(tester, lang: lang);
      await tester.tap(find.byKey(const Key('mark_button')));
      await tester.pumpAndSettle();
      await _capture(tester,
          fileName: out('03'),
          boxes: [find.byType(TextField), find.byType(Checkbox)],
          arrows: [(find.byType(TextField), _ArrowDir.nw)]);
    });

    Future<void> captureTemplatePanel(
        WidgetTester tester, TemplateType type, String step) async {
      await _pumpApp(tester, lang: lang);
      final panel = _templatePanel(type);
      await _ensureVisible(tester, panel);
      final panelRect = tester.getRect(panel);
      await _capture(tester,
          fileName: out(step),
          boxes: [find.byKey(Key('template_add_${type.name}'))],
          arrows: [
            (find.byKey(Key('template_add_${type.name}')), _ArrowDir.nw)
          ],
          cropOf: (_) => panelRect.inflate(14));
    }

    testWidgets('guide[$code] 04 startup template', (tester) async {
      await captureTemplatePanel(tester, TemplateType.startup, '04');
    });

    testWidgets('guide[$code] 05 transition template', (tester) async {
      await captureTemplatePanel(tester, TemplateType.transition, '05');
    });

    testWidgets('guide[$code] 06 ending template', (tester) async {
      await captureTemplatePanel(tester, TemplateType.ending, '06');
    });

    testWidgets('guide[$code] 07 background music', (tester) async {
      await captureTemplatePanel(tester, TemplateType.backgroundMusic, '07');
    });

    testWidgets('guide[$code] 08 "I want to" menu → Make', (tester) async {
      final container = await _pumpApp(tester, lang: lang);
      await container.read(recordProvider.notifier).addTimeslot(
            videoSourceId: 'guide-src',
            inPointMs: 32000,
            outPointMs: 42000,
            filename: 'test1.mp4',
            description: lang == '中文' ? '精彩瞬间' : 'Highlight moment',
            elapse: 10000,
          );
      await tester.pump();
      final l10n = container.read(l10nProvider);
      // Make / Result Folder buttons are gone (issues.md): the Make flow now
      // lives behind the "I want to" menu in the control panel. We capture the
      // open menu instead of the resolution dialog — that flow runs async
      // ffmpeg discovery which never completes under the widget-test clock.
      await tester.tap(find.byKey(const Key('want_menu')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.wantMake), findsOneWidget,
          reason: 'Make entry must be visible in the "I want to" menu');
      await _capture(tester,
          fileName: out('08'),
          boxes: [find.text(l10n.wantMake)],
          extraBoxes: [_unionRect(tester, find.byType(PopupMenuItem<String>))],
          arrows: [(find.text(l10n.wantMake), _ArrowDir.nw)]);
    });
  }
}
