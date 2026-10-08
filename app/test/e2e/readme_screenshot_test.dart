// Regenerates the README banner screenshots (app\windows\res\screenshot_*.png)
// for the English and Chinese UI.
//
// Pumps the real MainWindow with a fake player and in-memory settings, then
// populates a project with 4K sources and timeslots so the shot shows the app
// in use, captures the full window via a RepaintBoundary and writes PNGs.
//
// Run with:  flutter test test/e2e/readme_screenshot_test.dart
// (The test always writes the PNGs; nothing is skipped when images change.)

import 'dart:io' show Directory, File, Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/database/database.dart'
    show AppDatabase;
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/data/settings_service.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/main.dart';
import 'package:highlight_creator/presentation/player/player_state.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';

const _screen = Size(1280, 720);
const _scale = 2.0; // render at 2x so the README images stay crisp

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
        videoPath: r'C:\Videos\match1.mp4',
        position: Duration(seconds: 42),
        duration: Duration(minutes: 90),
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

/// Register real fonts: widget tests default to Ahem, which renders text and
/// icons as boxes — useless for screenshots.
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

/// Populate the default project with realistic 4K/full-HD sources and marked
/// timeslots so the capture shows the app in use.
Future<void> _populateProject(
    ProviderContainer container, String lang) async {
  final vm = container.read(recordProvider.notifier);
  await vm.createProject(lang == '中文' ? '欧冠决赛集锦' : 'UCL Final Highlights');
  final pid = container.read(recordProvider).selectedProjectId!;

  Future<void> addSource(String name, int durMs, int w, int h) => vm
      .addVideoSource(
        pid,
        VideoSource(
          id: '',
          projectId: pid,
          filePath: 'C:\\Videos\\$name',
          durationMs: durMs,
          width: w,
          height: h,
          codecName: 'h264',
          fps: 60,
          createdAt: DateTime.now(),
        ),
      );
  await addSource(r'match1.mp4', 5400000, 3840, 2160); // 90 min 4K60
  await addSource(r'match2.mp4', 3900000, 3840, 2160); // 65 min 4K60
  await addSource('matchHl.mp4', 300000, 1920, 1080); // assists reel 1080p60

  final slots = lang == '中文'
      ? ['快速反击', '世界波远射', '门线救险', '压哨绝杀']
      : ['Fast break', 'Long-range strike', 'Goal-line save', 'Last-minute winner'];
  Future<void> addSlot(int at, String desc, bool remote) => vm.addTimeslot(
        videoSourceId: '',
        inPointMs: at,
        outPointMs: at + 10000,
        filename: r'match1.mp4',
        description: desc,
        elapse: 10000,
        remote: remote,
      );
  await addSlot(420000, slots[0], true);
  await addSlot(900000, slots[1], false);
  await addSlot(1500000, slots[2], false);
  await addSlot(2600000, slots[3], true);
  await container.read(recordProvider.notifier).refreshProjects();
}

Future<void> _capture(
  WidgetTester tester, {
  required String fileName,
}) async {
  final boundaryFinder = find.byKey(const Key('capture_root'));
  await tester.pump();

  final written = await tester.runAsync<int>(() async {
    final boundary =
        tester.renderObject(boundaryFinder) as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _scale);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    final out = File(
        '${_resolveProjectRoot()}\\app\\windows\\res\\$fileName');
    out.createSync(recursive: true);
    await out.writeAsBytes(bytes!.buffer.asUint8List());
    return out.lengthSync();
  });

  expect(written, greaterThan(2000), reason: '$fileName too small');
}

void main() {
  setUpAll(() async {
    await _loadFonts();
    if (!locator.isRegistered<AppDatabase>()) {
      await initializeDependenciesFallback();
    }
  });

  for (final lang in const ['中文', 'English']) {
    final code = lang == '中文' ? 'zh' : 'en';

    testWidgets('readme screenshot[$code] main window', (tester) async {
      final container = await _pumpApp(tester, lang: lang);
      await _populateProject(container, lang);
      await tester.pumpAndSettle();
      await _capture(tester, fileName: 'screenshot_$code.png');

      // Flush PlayerScreen's 3 s "hide controls" timer so the test teardown
      // doesn't trip the pending-timer invariant.
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  }
}