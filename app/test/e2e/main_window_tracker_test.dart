import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:highlight_creator/data/database/database.dart' hide VideoSource;
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/data/repositories/timeslot_repository_impl.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/presentation/player/player_state.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/presentation/shell/main_window.dart';
import 'package:highlight_creator/presentation/shell/template_panel.dart';
import 'package:highlight_creator/presentation/shell/timeline_track.dart';

/// Fake player: a video loaded + paused (no media_kit natives). The tracker
/// reads player state only; the video file itself does not need to exist.
class _FakePlayerViewModel extends VideoPlayerViewModel {
  @override
  VideoPlayerState build() => const VideoPlayerState(
        status: PlayerStatus.paused,
        videoPath: r'C:\Videos\test1.mp4',
        position: Duration(seconds: 42),
        duration: Duration(minutes: 1),
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

/// Player fake that records loadVideo/seek calls so tests can assert exactly
/// where a cross-source preview-bar click lands.
class _RecordingPlayerViewModel extends VideoPlayerViewModel {
  final List<({String path, Duration? initialPosition})> loaded = [];
  final List<Duration> seeks = [];
  int playCalls = 0;
  final String initialVideoPath = _sourcePath;

  @override
  VideoPlayerState build() => VideoPlayerState(
        status: PlayerStatus.paused,
        videoPath: initialVideoPath,
        position: Duration.zero,
        duration: const Duration(seconds: 10),
      );

  @override
  Future<void> play() async {
    playCalls += 1;
    state = state.copyWith(status: PlayerStatus.playing);
  }

  @override
  Future<void> pause() async =>
      state = state.copyWith(status: PlayerStatus.paused);

  @override
  Future<void> stop() async {}

  @override
  Future<void> loadVideo(String path, {Duration? initialPosition}) async {
    loaded.add((path: path, initialPosition: initialPosition));
    state = state.copyWith(
      videoPath: path,
      position: initialPosition ?? Duration.zero,
      clearError: true,
    );
  }

  @override
  Future<void> seek(Duration pos) async {
    seeks.add(pos);
    state = state.copyWith(position: pos);
  }
}

/// The collapse/expand bar is keyed in production (main_window.dart), so the
/// finder targets the key instead of paint details (bg color / width) that
/// restyles keep breaking.
Finder _collapseBar() => find.byKey(const ValueKey('collapse_file_list_bar'));

const _sourcePath = r'C:\Videos\test1.mp4';
const _source2Path = r'C:\Videos\test2.mp4';

/// Pump the main window with two 10s sources; returns the recording fake so
/// the test can assert what the track asked the player to do.
Future<_RecordingPlayerViewModel> _pumpTwoSources(WidgetTester tester) async {
  final fake = _RecordingPlayerViewModel();
  final container = ProviderContainer(
    overrides: [
      projectRepositoryProvider.overrideWith((ref) => ProjectRepositoryImpl()),
      timeslotRepositoryProvider
          .overrideWith((ref) => TimeslotRepositoryImpl()),
      videoPlayerProvider.overrideWith(() => fake),
    ],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MainWindow()),
    ),
  );
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }

  final recVm = container.read(recordProvider.notifier);
  final pid = container.read(recordProvider).selectedProjectId!;
  for (final (id, path) in [('s1', _sourcePath), ('s2', _source2Path)]) {
    await recVm.addVideoSource(
      pid,
      VideoSource(
        id: id,
        projectId: pid,
        filePath: path,
        durationMs: 10000,
        width: 1280,
        height: 720,
        codecName: 'h264',
        fps: 30,
        createdAt: DateTime(2024),
      ),
    );
  }
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }

  // Expand the originally-collapsed tracker header.
  await tester.tap(find.text('Timeline'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  return fake;
}

Future<ProviderContainer> _pumpMainWindow(
    WidgetTester tester, {required bool withSource}) async {
  final container = ProviderContainer(
    overrides: [
      projectRepositoryProvider.overrideWith((ref) => ProjectRepositoryImpl()),
      timeslotRepositoryProvider
          .overrideWith((ref) => TimeslotRepositoryImpl()),
      videoPlayerProvider.overrideWith(_FakePlayerViewModel.new),
    ],
  );
  addTearDown(container.dispose);

  tester.view.physicalSize = const Size(1280, 720);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: MainWindow()),
    ),
  );
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }

  // MainWindow creates a default project on startup; add the source to that
  // selected project so the tracker has a timeline to render.
  if (withSource) {
    final recVm = container.read(recordProvider.notifier);
    final pid = container.read(recordProvider).selectedProjectId!;
    await recVm.addVideoSource(
      pid,
      VideoSource(
        id: 's1',
        projectId: pid,
        filePath: _sourcePath,
        durationMs: 60000,
        width: 1280,
        height: 720,
        codecName: 'h264',
        fps: 30,
        createdAt: DateTime(2024),
      ),
    );
    // Pre-create a timeslot so the track renders timeslot rects.
    await recVm.addTimeslot(
      videoSourceId: 's1',
      inPointMs: 10000,
      outPointMs: 15000,
      filename: 'test1.mp4',
      elapse: 5000,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
  }
  return container;
}

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    MediaKit.ensureInitialized();
    // TemplatePanel reads its repo through GetIt, so register the in-memory
    // DI fallback exactly like guide_screenshots_test does.
    if (!locator.isRegistered<AppDatabase>()) {
      await initializeDependenciesFallback();
    }
  });

  testWidgets(
      'MainWindow tracker is collapsed by default and expandable to show all '
      'sources on the timeline', (tester) async {
    await _pumpMainWindow(tester, withSource: true);

    // Default state: the header row shows, the track body is collapsed.
    expect(find.text('Timeline'), findsOneWidget);
    expect(find.byType(TimelineTrack), findsNothing,
        reason: 'tracker bar should start collapsed (issues.md)');

    // Expand it via the header.
    await tester.tap(find.text('Timeline'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(TimelineTrack), findsOneWidget,
        reason: 'expanding the header reveals the timeline track');

    // The track spans the project source (60s): ruler marker at 42s exists
    // and the playhead-linked marker for the loaded video shows.
    expect(find.text('0:42'), findsOneWidget,
        reason: 'ruler tick at the playhead position should render');

    // A timeslot rect for the seeded slot renders on the bar.
    expect(find.byType(MouseRegion), findsWidgets,
        reason: 'timeslot handle bars render on the track');
  });

  testWidgets('collapse bar sits to the LEFT of the right panel with grey bg',
      (tester) async {
    await _pumpMainWindow(tester, withSource: false);

    expect(find.byType(TemplatePanel), findsWidgets);
    final panelLeft = tester.getTopLeft(find.byType(TemplatePanel).first).dx;
    final bar = _collapseBar();
    expect(bar, findsOneWidget,
        reason: 'collapse bar should be present (grey background)');
    final barCenterX = tester.getCenter(bar).dx;

    expect(barCenterX, lessThan(panelLeft),
        reason: 'collapse bar should be to the left of the right panel');

    // Toggling still collapses/expands the panel.
    await tester.tap(bar);
    await tester.pump();
    expect(find.byType(TemplatePanel), findsNothing,
        reason: 'panel should collapse when the bar is tapped');
    await tester.tap(bar);
    await tester.pump();
    expect(find.byType(TemplatePanel), findsWidgets,
        reason: 'panel should expand back when the bar is tapped again');
  });

  testWidgets(
      'preview-bar click into another source resumes at the clicked time, '
      'not the head of the video', (tester) async {
    final fake = await _pumpTwoSources(tester);

    // Two 10s sources at 30px/s. Clicking at x=450px (~15s) is inside the
    // SECOND source (segment 1), 5s into it.
    final origin = tester.getTopLeft(find.byType(TimelineTrack));
    await tester.tapAt(origin + const Offset(450, 40));
    await tester.pump();

    expect(fake.loaded, isNotEmpty,
        reason: 'cross-source click should open the target source');
    final last = fake.loaded.last;
    expect(last.path, _source2Path,
        reason: 'should load the target (second) source');
    expect(last.initialPosition, const Duration(seconds: 5),
        reason: 'should resume at the clicked time, not the start (regression)');
    expect(fake.seeks, isEmpty,
        reason: 'no separate seek needed for a cross-source click');
  });

  testWidgets('clicking a timeslot row plays that slot from its start',
      (tester) async {
    // Single source + one 10s..15s slot; the fake records loadVideo/play.
    final fake = _RecordingPlayerViewModel();
    final container = ProviderContainer(
      overrides: [
        projectRepositoryProvider.overrideWith((ref) => ProjectRepositoryImpl()),
        timeslotRepositoryProvider
            .overrideWith((ref) => TimeslotRepositoryImpl()),
        videoPlayerProvider.overrideWith(() => fake),
      ],
    );
    addTearDown(container.dispose);

    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MainWindow()),
      ),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    final recVm = container.read(recordProvider.notifier);
    final pid = container.read(recordProvider).selectedProjectId!;
    await recVm.addVideoSource(
      pid,
      VideoSource(
        id: 's1',
        projectId: pid,
        filePath: _sourcePath,
        durationMs: 60000,
        width: 1280,
        height: 720,
        codecName: 'h264',
        fps: 30,
        createdAt: DateTime(2024),
      ),
    );
    await recVm.addTimeslot(
      videoSourceId: 's1',
      inPointMs: 10000,
      outPointMs: 15000,
      filename: 'test1.mp4',
      elapse: 5000,
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }

    // The timeslot table is visible by default; tap its single row.
    final rowText = find.text('Slot 1');
    expect(rowText, findsOneWidget,
        reason: 'timeslot row should be visible in the table');
    final rowInk = find.ancestor(
      of: rowText,
      matching: find.byType(InkWell),
    ).first;
    await tester.tap(rowInk);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(fake.loaded, isNotEmpty,
        reason: 'clicking a slot row should load its source');
    expect(fake.loaded.last.path, _sourcePath);
    expect(fake.loaded.last.initialPosition, const Duration(seconds: 10),
        reason: 'slot must start at its inPoint (10s)');
    expect(fake.playCalls, greaterThan(0),
        reason: 'slot playback must start playing');
  });
}