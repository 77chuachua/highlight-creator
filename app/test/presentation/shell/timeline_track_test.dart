import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/data/repositories/timeslot_repository_impl.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/presentation/shell/timeline_track.dart';

/// Timeline track seek behavior (issues.md): clicking the track background —
/// AND clicking a timeslot body — seeks to the exact clicked time (not the
/// slot start). Pure widget test, no ffmpeg/fixtures needed.
void main() {
  late int captured;

  // The slot-body GestureDetector is the one wrapping a Stack that contains a
  // Positioned->MouseRegion (the drag handle bars).
  Finder slotBody() => find.byWidgetPredicate((w) =>
      w is GestureDetector &&
      w.child is Stack &&
      (w.child as Stack).children
          .any((c) => c is Positioned && c.child is MouseRegion));

  Future<void> pumpTrack(WidgetTester tester, {int globalPositionMs = 0}) async {
    final projectRepo = ProjectRepositoryImpl();
    final timeslotRepo = TimeslotRepositoryImpl();
    final container = ProviderContainer(
      overrides: [
        projectRepositoryProvider.overrideWith((ref) => projectRepo),
        timeslotRepositoryProvider.overrideWith((ref) => timeslotRepo),
      ],
    );
    addTearDown(container.dispose);

    final recVm = container.read(recordProvider.notifier);
    await recVm.createProject('p1');
    final pid = container.read(recordProvider).selectedProjectId!;
    await recVm.addVideoSource(
      pid,
      VideoSource(
        id: 's1',
        projectId: pid,
        filePath: 'C:\\Videos\\test1.mp4',
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

    tester.view.physicalSize = const Size(800, 200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, useMaterial3: true),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: TimelineTrack(
                sources:
                    container.read(recordProvider).selectedProject!.sources,
                durationsMs: const [60000],
                previewPaths: const [],
                globalPositionMs: globalPositionMs,
                segmentOf: (_) => 0,
                onTrackTap: (ms) => captured = ms,
                onCommitDrag: (_, __, ___, ____) {},
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('clicking the track background seeks to the exact time',
      (tester) async {
    captured = -1;
    await pumpTrack(tester);

    final origin = tester.getTopLeft(find.byType(TimelineTrack));
    // 150px @ 30px/s = 5s. Click lands on the preview-bar background (its
    // grey layer spans y from below the ruler to the bar bottom).
    await tester.tapAt(origin + const Offset(150, 40));
    await tester.pump();

    expect(captured, 5000,
        reason: 'background click should seek to the clicked time');
  });

  testWidgets('clicking a timeslot seeks to the clicked time, not slot start',
      (tester) async {
    captured = -1;
    await pumpTrack(tester);

    final origin = tester.getTopLeft(find.byType(TimelineTrack));
    final slot = slotBody();
    expect(slot, findsOneWidget, reason: 'a timeslot rect should render');
    final center = tester.getRect(slot).center;

    // Slot spans 10s..15s (300..450px). Clicking its center maps to 12.5s.
    final clickedMs = ((center.dx - origin.dx) / 30 * 1000).round();
    await tester.tapAt(center);
    await tester.pump();

    expect(captured, clickedMs,
        reason: 'slot click should seek to the clicked time');
    expect(captured, isNot(10000),
        reason: 'it must NOT seek to the slot start time');
  });

  // Issue: jumping the playhead far (e.g. from video 1 to video 10) used to
  // step the scroll by half a viewport per frame (~10s of scrolling). It must
  // snap straight to the playhead in a single frame.
  testWidgets(
      'playhead far outside the viewport snaps the track instead of stepping',
      (tester) async {
    await pumpTrack(tester, globalPositionMs: 50000);

    // Track is 60s@30px/s = 1800px in an 800px viewport → maxScroll 1000.
    // Playhead at 50s = 1500px is far outside the initial viewport; after the
    // first build the scroll must already rest at the far edge (1000px), not
    // at a half-viewport step (400px).
    final scrollable =
        tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, 1000,
        reason:
            'track must snap to the playhead in one frame, not scroll ~10s');
  });

  group('globalToLocal', () {
    const durations = [60000, 30000, 10000]; // 60s, 30s, 10s segments

    test('maps position inside first segment', () {
      final r = globalToLocal(durations, 5000);
      expect(r.index, 0);
      expect(r.localMs, 5000);
    });

    test('maps position in middle segment', () {
      final r = globalToLocal(durations, 75000); // 60s + 15s
      expect(r.index, 1);
      expect(r.localMs, 15000);
    });

    test('maps position in last segment', () {
      final r = globalToLocal(durations, 95000); // 60s + 30s + 5s
      expect(r.index, 2);
      expect(r.localMs, 5000);
    });

    test('segment boundary goes to the next segment', () {
      final r = globalToLocal(durations, 60000);
      expect(r.index, 1);
      expect(r.localMs, 0);
    });

    test('clamps negative to start of first segment', () {
      final r = globalToLocal(durations, -100);
      expect(r.index, 0);
      expect(r.localMs, 0);
    });

    test('clamps past total to end of last segment', () {
      final r = globalToLocal(durations, 999999);
      expect(r.index, 2);
      expect(r.localMs, 10000);
    });

    test('single segment', () {
      final r = globalToLocal([45000], 20000);
      expect(r.index, 0);
      expect(r.localMs, 20000);
    });

    test('empty durations returns safe default', () {
      final r = globalToLocal([], 5000);
      expect(r.index, 0);
      expect(r.localMs, 0);
    });
  });
}