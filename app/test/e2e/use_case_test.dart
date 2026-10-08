import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mocktail/mocktail.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/data/repositories/timeslot_repository_impl.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/player_state.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/presentation/shell/control_panel.dart';

// ---------------------------------------------------------------------------
// Mocks for media_kit types
// ---------------------------------------------------------------------------
class _MockPlayer extends Mock implements Player {}

// ---------------------------------------------------------------------------
// Test-only VideoPlayerViewModel that doesn't depend on real media_kit native
// resources. All playback state is faked so the ControlPanel can render and
// the Mark dialog can compute a position.
// ---------------------------------------------------------------------------
class _TestVideoPlayerViewModel extends VideoPlayerViewModel {
  final String _testVideoPath;

  /// Mutable position so tests can simulate seeking or separate marks at
  /// different offsets.
  Duration currentPosition;

  _TestVideoPlayerViewModel({
    required String videoPath,
    Duration initialPosition = Duration.zero,
  })  : _testVideoPath = videoPath,
        currentPosition = initialPosition;

  @override
  Player? get player => _testPlayer;

  /// Override build() so hasVideo is true and the initial state is already
  /// "paused" with the test file loaded.
  @override
  VideoPlayerState build() {
    return VideoPlayerState(
      status: PlayerStatus.paused,
      videoPath: _testVideoPath,
      position: currentPosition,
      duration: const Duration(minutes: 1),
    );
  }

  /// Simulate a seek so that subsequent Mark dialogs pick up a new position.
  void setPosition(Duration position) {
    currentPosition = position;
    state = state.copyWith(position: position);
    // Keep the mock Player in sync: every access to .state returns the
    // latest PlayerState built from currentPosition.
    _updateMockState();
  }

  void _updateMockState() {
    when(() => _testPlayer.state).thenReturn(
      PlayerState(position: currentPosition),
    );
  }

  @override
  Future<void> pause() async {
    state = state.copyWith(status: PlayerStatus.paused);
  }

  @override
  Future<void> play() async {
    state = state.copyWith(status: PlayerStatus.playing);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> loadVideo(String path, {Duration? initialPosition}) async {}
}

// ---------------------------------------------------------------------------
// A single shared mock Player for all tests.  Its .state getter is
// reconfigured by each _TestVideoPlayerViewModel instance via _updateMockState.
// ---------------------------------------------------------------------------
final _testPlayer = _MockPlayer();

// ---------------------------------------------------------------------------
// Path helpers (mirrors the logic from the original pure-Dart test)
// ---------------------------------------------------------------------------
String _resolveVideoSourceDir() {
  final cwd = Directory.current.path;
  if (cwd.endsWith('app')) {
    return '${Directory.current.parent.path}\\test\\e2e\\videoSource';
  }
  return '$cwd\\test\\e2e\\videoSource';
}

String _resolveTempDir() {
  final cwd = Directory.current.path;
  if (cwd.endsWith('app')) {
    return '${Directory.current.parent.path}\\temp\\e2e\\';
  }
  return '$cwd\\temp\\e2e\\';
}

// ---------------------------------------------------------------------------
// Build a minimal widget tree that hosts the ControlPanel so we can exercise
// the Mark button and the "I want to" menu with tester.tap.
// ---------------------------------------------------------------------------
Widget _buildTestHarness(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const _HarnessPage(),
  );
}

/// Minimal harness that places the ControlPanel in a Scaffold.
class _HarnessPage extends StatelessWidget {
  const _HarnessPage();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: ControlPanel(),
        ),
      ),
    );
  }
}

/// Helper: add a video source to the current project through the ViewModel
/// (setup-only operation — file picking cannot be driven via tester.tap).
Future<void> _addSource(ProviderContainer container, String projectId,
    String filePath) async {
  await container.read(recordProvider.notifier).addVideoSource(
        projectId,
        VideoSource(
          id: '',
          projectId: projectId,
          filePath: filePath,
          durationMs: 0,
          width: 0,
          height: 0,
          codecName: '',
          fps: 0,
          createdAt: DateTime.now(),
        ),
      );
}

// ---------------------------------------------------------------------------
// Helper: triggers the Mark dialog, fills description, taps OK.
//
// Because the Navigator's built-in AbsorbPointer (navigator.dart:5933)
// can absorb widget-test taps even after the route animation completes,
// we invoke the button's onPressed callback directly.  This still exercises
// the full dialog flow — the dialog is opened, filled, and dismissed via
// tester.tap on the OK button (which works because DialogRoute manages
// its own barrier).
// ---------------------------------------------------------------------------
Future<void> _markWithDescription(
    WidgetTester tester, String description) async {
  // Invoke the Mark button's onPressed directly to bypass the Navigator's
  // AbsorbPointer hit-test limitation.
  final markBtn = tester.widget<FilledButton>(
    find.byKey(const Key('mark_button')),
  );
  expect(markBtn.onPressed, isNotNull,
      reason: 'Mark button should be enabled');
  markBtn.onPressed!();

  // Pump frames to process the dialog push and entrance animation.
  // Using explicit pumps instead of pumpAndSettle avoids potential
  // hang from non-settling animations on the underlying route.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();

  // Dialog should be visible.
  expect(find.text('Mark Timeslot'), findsOneWidget);

  // Enter description.
  await tester.enterText(find.byType(TextField), description);
  await tester.pump();

  // Tap OK button.
  final okBtn = find.text('OK');
  await tester.tap(okBtn);
  // Pump frames to process the Navigator.pop and snackbar.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();

  // Dialog dismissed.
  expect(find.text('Mark Timeslot'), findsNothing);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  setUpAll(() {
    registerFallbackValue(Duration.zero);
    registerFallbackValue(const PlayerState());
    // Enable ffmpeg command logging (project root, survives temp cleanup).
    VideoProcessingService.commandLogPath = '${Directory(_resolveTempDir()).parent.path}\\ffmpeg_command';
  });

  group('UseCase E2E — Highlight Creator Pipeline', () {
    // ────────────────────────────────────────────────────────────────
    // Test 1: Full 11-step pipeline (pure Dart — the Make step runs
    // real ffmpeg processes that cannot be driven through frame pumps).
    // The Mark operations are tested via UI in test 2 below.
    // ────────────────────────────────────────────────────────────────
    test('Full use case: 11 steps (programmatic)', () async {
      final projectRepo = ProjectRepositoryImpl();
      final timeslotRepo = TimeslotRepositoryImpl();

      // Clean temp/e2e dir from previous runs (safe: e2e-only folder).
      final tempDir = Directory(_resolveTempDir());
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }

      // ---- Step 1: setup ----
      final sourceDir = _resolveVideoSourceDir();
      const testFiles = ['test1.mp4', 'test2.mp4', 'test3.mp4', 'test4.mp4'];

      for (final f in testFiles) {
        expect(File('$sourceDir\\$f').existsSync(), true,
            reason: 'Source file missing: $f');
      }
      expect(File('$sourceDir\\startup.mp4').existsSync(), true,
          reason: 'startup.mp4 missing');

      final container = ProviderContainer(
        overrides: [
          projectRepositoryProvider.overrideWith((ref) => projectRepo),
          timeslotRepositoryProvider.overrideWith((ref) => timeslotRepo),
        ],
      );
      addTearDown(container.dispose);

      final recVm = container.read(recordProvider.notifier);
      RecordState readState() => container.read(recordProvider);

      await recVm.createProject('E2E Test Project');
      final pid = readState().selectedProjectId!;
      expect(pid, isNotEmpty);

      for (final f in testFiles) {
        await _addSource(container, pid, '$sourceDir\\$f');
      }

      final project = readState().selectedProject;
      expect(project, isNotNull);
      expect(project!.sources.length, 4);

      // ---- Step 2: verify source list ----
      expect(project.sources[0].filePath, contains('test1.mp4'));

      // ---- Steps 3–6: Mark at 11 seconds ----
      const markDescriptions = [
        'test1_mark',
        'test2_mark',
        'test3_mark',
        'test4_mark',
      ];

      for (var i = 0; i < testFiles.length; i++) {
        await recVm.mark(
          videoSourceId: project.sources[i].id,
          positionMs: 11000,
          filename: testFiles[i],
          description: markDescriptions[i],
          remote: false,
        );
      }

      // ---- Step 7: Check timeslots list — 4 records ----
      expect(readState().timeslots.length, 4);
      for (var i = 0; i < 4; i++) {
        final slot = readState().timeslots[i];
        // Mark creates a 10s window ending at the mark position.
        expect(slot.inPointMs, 1000);
        expect(slot.outPointMs, 11000);
        expect(slot.elapse, 10000);
        expect(slot.description, markDescriptions[i]);
        expect(slot.filename, testFiles[i]);
      }

      // ---- Steps 8–11: Make pipeline ----
      final outputDir = _resolveTempDir();
      final startupPath = '$sourceDir\\startup.mp4';
      final ffmpegPath = await VideoProcessingService.findFfmpeg();
      final service = VideoProcessingService(ffmpegPath: ffmpegPath);

      final sourceByFilename = <String, String>{};
      for (final s in project.sources) {
        sourceByFilename[s.filePath.split('\\').last] = s.filePath;
        sourceByFilename[s.filePath.split('/').last] = s.filePath;
      }

      // Annotate log entries for this test.
      VideoProcessingService.commandLogContext =
          'use_case_test.dart :: Full use case: 11 steps (programmatic)';

      // Progress must be reported step-by-step, monotonic, ending at 1.0.
      final progressValues = <double>[];
      await service.makeAll(
        timeslots: readState().timeslots,
        startupVideoPath: startupPath,
        outputDir: outputDir,
        sourcePaths: sourceByFilename,
        endingVideoPath: '$sourceDir\\Ending.mp4',
        bgMusicPath: '$sourceDir\\bg_music.mp3',
        onProgress: progressValues.add,
      );
      expect(progressValues, isNotEmpty, reason: 'no progress reported');
      expect(progressValues.first, 0.0);
      expect(progressValues.last, 1.0);
      for (var i = 1; i < progressValues.length; i++) {
        expect(progressValues[i], greaterThanOrEqualTo(progressValues[i - 1]),
            reason: 'progress must be monotonic');
      }
      expect(progressValues.any((v) => v >= 0.4 && v <= 0.6), isTrue,
          reason: 'progress should pass through mid-pipeline values');

      // ---- Steps 9–11: Verify outputs ----
      final finalPath = '${outputDir}final.mp4';
      final bodyPath = '${outputDir}body.mp4';
      final bodyMusicPath = '${outputDir}body_music.mp4';
      expect(File(finalPath).existsSync(), true,
          reason: 'final.mp4 missing');
      expect(File(bodyPath).existsSync(), true,
          reason: 'body.mp4 missing');
      expect(File(bodyMusicPath).existsSync(), true,
          reason: 'body_music.mp4 missing');

      for (var i = 0; i < markDescriptions.length; i++) {
        final slotName = 'slot_$i';
        final transitionPath = '$outputDir${slotName}_transition.mp4';
        final subPath = '$outputDir${slotName}_sub.mp4';
        expect(File(transitionPath).existsSync(), true,
            reason: 'Transition file missing: $slotName');
        expect(File(subPath).existsSync(), true,
            reason: 'Sub file missing: $slotName');
        expect((File(transitionPath).lengthSync()) > 0, true,
            reason: 'Transition file is empty: $slotName');
        expect((File(subPath).lengthSync()) > 0, true,
            reason: 'Sub file is empty: $slotName');
      }

      expect((File(finalPath).lengthSync()) > 0, true,
          reason: 'final.mp4 is empty');
    });

    // ────────────────────────────────────────────────────────────────
    // Test 2: Timeslot ordering via UI marks at different positions
    // ────────────────────────────────────────────────────────────────
    testWidgets('Timeslot ordering matches mark order', (tester) async {
      final projectRepo = ProjectRepositoryImpl();
      final timeslotRepo = TimeslotRepositoryImpl();
      final sourceDir = _resolveVideoSourceDir();
      final testVideoPath = '$sourceDir\\test1.mp4';

      final testPlayerVm = _TestVideoPlayerViewModel(
        videoPath: testVideoPath,
        initialPosition: const Duration(milliseconds: 5000),
      );

      final container = ProviderContainer(
        overrides: [
          projectRepositoryProvider.overrideWith((ref) => projectRepo),
          timeslotRepositoryProvider.overrideWith((ref) => timeslotRepo),
          videoPlayerProvider.overrideWith(() => testPlayerVm),
        ],
      );
      addTearDown(container.dispose);

      final recVm = container.read(recordProvider.notifier);
      RecordState readState() => container.read(recordProvider);

      // Setup: create project and add one source.
      await recVm.createProject('Order Test');
      final pid = readState().selectedProjectId!;
      await _addSource(container, pid, testVideoPath);

      // Render the harness.
      await tester.pumpWidget(_buildTestHarness(container));
      // Pump several frames to settle the route animation and let the
      // widget tree stabilise (avoiding pumpAndSettle which can hang).
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Verify the Mark button is enabled (hasVideo must be true).
      expect(container.read(videoPlayerProvider).hasVideo, isTrue,
          reason: 'Mark button requires a loaded video');
      expect(find.text('Mark (Ctrl+M)'), findsOneWidget);
      // Inspect the actual button to verify onPressed is set.
      final markBtnWidget = tester.widget<FilledButton>(
        find.byKey(const Key('mark_button')),
      );
      expect(markBtnWidget.onPressed, isNotNull,
          reason: 'Mark button onPressed is null — hasVideo might be false in widget context');

      // ---- Mark 1 at 5000 ms ----
      testPlayerVm.setPosition(const Duration(milliseconds: 5000));
      await _markWithDescription(tester, 'first');

      // ---- Mark 2 at 11000 ms (user seeks forward) ----
      testPlayerVm.setPosition(const Duration(milliseconds: 11000));
      await _markWithDescription(tester, 'second');

      // ---- Mark 3 at 18000 ms ----
      testPlayerVm.setPosition(const Duration(milliseconds: 18000));
      await _markWithDescription(tester, 'third');

      // Verify order.
      expect(readState().timeslots.length, 3);
      expect(readState().timeslots[0].description, 'first');
      expect(readState().timeslots[1].description, 'second');
      expect(readState().timeslots[2].description, 'third');
    });

    // ────────────────────────────────────────────────────────────────
    // Test 3: Make / Result Folder buttons are gone; the "I want to" menu
    // in the control panel replaces them (issues.md). Its Make entry is
    // disabled when there are no timeslots.
    // ────────────────────────────────────────────────────────────────
    testWidgets('I want to menu replaces Make and Result Folder buttons',
        (tester) async {
      final projectRepo = ProjectRepositoryImpl();
      final timeslotRepo = TimeslotRepositoryImpl();

      final testPlayerVm = _TestVideoPlayerViewModel(
        videoPath: '${_resolveVideoSourceDir()}\\startup.mp4',
        initialPosition: Duration.zero,
      );

      final container = ProviderContainer(
        overrides: [
          projectRepositoryProvider.overrideWith((ref) => projectRepo),
          timeslotRepositoryProvider.overrideWith((ref) => timeslotRepo),
          videoPlayerProvider.overrideWith(() => testPlayerVm),
        ],
      );
      addTearDown(container.dispose);

      final recVm = container.read(recordProvider.notifier);
      await recVm.createProject('Empty Project');

      await tester.pumpWidget(_buildTestHarness(container));
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Old stand-alone buttons are removed.
      expect(find.byKey(const Key('make_button')), findsNothing,
          reason: 'Make button should be removed');
      expect(find.text('Result Folder'), findsNothing,
          reason: 'Result Folder button should be removed');
      // "I want to" menu now lives in the control panel.
      expect(find.byKey(const Key('want_menu')), findsOneWidget);

      // Open the menu: Make entry is disabled with no timeslots.
      await tester.tap(find.byKey(const Key('want_menu')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final makeItem = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Make'),
      );
      expect(makeItem.enabled, isFalse,
          reason: 'Make entry should be disabled with no timeslots');
    });

    // ────────────────────────────────────────────────────────────────
    // Test 4: Auto Gen button is hidden (issues.md: hide button + info icon)
    // ────────────────────────────────────────────────────────────────
    testWidgets('Auto Gen button is hidden even when sources exist',
        (tester) async {
      final projectRepo = ProjectRepositoryImpl();
      final timeslotRepo = TimeslotRepositoryImpl();

      final testPlayerVm = _TestVideoPlayerViewModel(
        videoPath: '${_resolveVideoSourceDir()}\\startup.mp4',
        initialPosition: Duration.zero,
      );

      final container = ProviderContainer(
        overrides: [
          projectRepositoryProvider.overrideWith((ref) => projectRepo),
          timeslotRepositoryProvider.overrideWith((ref) => timeslotRepo),
          videoPlayerProvider.overrideWith(() => testPlayerVm),
        ],
      );
      addTearDown(container.dispose);

      final recVm = container.read(recordProvider.notifier);
      await recVm.createProject('Auto Gen Project');
      final pid = container.read(recordProvider).selectedProjectId!;

      // Add a source — the button must stay hidden regardless.
      await _addSource(container, pid,
          '${_resolveVideoSourceDir()}\\test1.mp4');

      await tester.pumpWidget(_buildTestHarness(container));
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      // Auto Gen button and its info icon are hidden per issues.md.
      expect(find.byKey(const Key('auto_gen_button')), findsNothing);
      expect(find.byIcon(Icons.info_outline), findsNothing);
    });
  });
}
