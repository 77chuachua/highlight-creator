import 'dart:io' show Directory, File;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/data/repositories/timeslot_repository_impl.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/presentation/shell/timeline_track.dart';
import 'package:highlight_creator/presentation/shell/timeslot_table.dart';

/// The main-window / timeline track replaced the auto-gen dialog, so the
/// preview-bar rendering + timeslot-rect behavior it previously covered now
/// lives in the shared `TimelineTrack`. The extractFrame tests stay real
/// ffmpeg e2e (used by the main-window tracker's preview thumbnails).
void main() {
  test('extractFrame produces valid preview images for a source', () async {
    final projectRoot = _resolveProjectRoot();
    final sourceDir = '$projectRoot\\test\\e2e\\videoSource';
    final tempDir = '$projectRoot\\temp\\e2e\\';

    final sourcePath = '$sourceDir\\test1.mp4';
    expect(File(sourcePath).existsSync(), isTrue,
        reason: 'Source video missing: $sourcePath');

    final dir = Directory(tempDir);
    if (!dir.existsSync()) await dir.create(recursive: true);

    VideoProcessingService.commandLogPath = '$projectRoot\\ffmpeg_command';
    VideoProcessingService.commandLogContext =
        'autogen_preview_test.dart :: extractFrame produces valid preview images';

    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    final service = VideoProcessingService(ffmpegPath: ffmpegPath);

    final outputPath = '${tempDir}autogen_preview_test.png';
    final result = await service.extractFrame(
      sourcePath: sourcePath,
      timestampSecs: 1.0,
      outputPath: outputPath,
      width: 160,
      height: 90,
    );

    expect(result.exitCode, 0,
        reason: 'ffmpeg failed:\n${result.stderr}');
    expect(File(outputPath).existsSync(), isTrue,
        reason: 'Preview PNG was not created: $outputPath');
    expect(File(outputPath).lengthSync(), greaterThan(1000),
        reason: 'Preview PNG too small — likely corrupt or empty');
  });

  test('extractFrame handles invalid source gracefully', () async {
    final projectRoot = _resolveProjectRoot();
    final tempDir = '$projectRoot\\temp\\e2e\\';

    final dir = Directory(tempDir);
    if (!dir.existsSync()) await dir.create(recursive: true);

    VideoProcessingService.commandLogContext =
        'autogen_preview_test.dart :: extractFrame handles invalid source gracefully';

    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    final service = VideoProcessingService(ffmpegPath: ffmpegPath);

    final outputPath = '${tempDir}autogen_preview_invalid.png';
    final result = await service.extractFrame(
      sourcePath: 'C:\\nonexistent\\video.mp4',
      timestampSecs: 1.0,
      outputPath: outputPath,
      width: 160,
      height: 90,
    );

    expect(result.exitCode, isNot(0),
        reason: 'ffmpeg should fail for non-existent source');
    expect(File(outputPath).existsSync(), isFalse,
        reason: 'Output file should not be created for invalid source');
  });

  // Regression: the preview bar used to wrap its playback position line in
  // IgnorePointer(Positioned(...)), which throws "Incorrect use of
  // ParentDataWidget". The track must render a grey track + a direct
  // positioned white playhead line.
  testWidgets('TimelineTrack preview bar renders grey track and position line',
      (tester) async {
    await _pumpTrack(tester, withSlot: false, globalPositionMs: 42000);

    // No ParentDataWidget exception while rendering.
    expect(tester.takeException(), isNull);

    final previewStack = find.byWidgetPredicate((w) =>
        w is Stack &&
        w.children.any((c) =>
            c is Positioned &&
            c.left == 0 &&
            c.right == 0 &&
            c.child is GestureDetector));
    expect(previewStack, findsOneWidget,
        reason: 'preview bar Stack not found — bar may not render');

    final stack = tester.widget<Stack>(previewStack);
    final bg = stack.children
        .whereType<Positioned>()
        .where((p) => p.left == 0 && p.right == 0)
        .map((p) => p.child)
        .expand((c) => c is GestureDetector ? [c.child] : const <Widget>[])
        .whereType<Container>()
        .toList();
    expect(bg, isNotEmpty,
        reason: 'preview bar should paint a grey background track');
    expect(bg.first.color, isNot(Colors.white),
        reason: 'preview bar background must not be white');

    final line = stack.children.whereType<Positioned>().where(
        (p) => p.width == 2 && p.top == 0 && p.bottom == 0);
    expect(line.length, 1,
        reason: 'playback position line must render as a direct Stack child');
  });

  // Issues.md: timeslots are drawn on the preview bar as rects at 60%
  // transparency, positioned/coloured from the seeded slot.
  testWidgets('TimelineTrack preview bar renders timeslots as transparent rects',
      (tester) async {
    await _pumpTrack(tester, withSlot: true);

    final previewStack = find.byWidgetPredicate((w) =>
        w is Stack &&
        w.children.any((c) =>
            c is Positioned &&
            c.left == 0 &&
            c.right == 0 &&
            c.child is GestureDetector));
    expect(previewStack, findsOneWidget);

    final stack = tester.widget<Stack>(previewStack);
    const expectedRectColor = Color(0x6642A5F5);
    final rect = stack.children
        .whereType<Positioned>()
        .where((p) => p.child is GestureDetector)
        .map((p) => (p.child as GestureDetector).child)
        .whereType<Stack>()
        .expand((s) => s.children)
        .whereType<Positioned>()
        .where((p) => p.child is Container)
        .map((p) => p.child as Container)
        .where((c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).color == expectedRectColor)
        .toList();
    expect(rect, isNotEmpty,
        reason: 'a timeslot rect with 60% transparency should be on the bar');
    expect((rect.first.decoration as BoxDecoration).color,
        TimeslotTable.colors[0].withAlpha(102),
        reason: 'timeslot rect should use the slot colour at 60% alpha');
  });

  // Issues.md: timeslots have two explicit draggable bars at start and end.
  testWidgets('TimelineTrack preview bar renders draggable handle bars',
      (tester) async {
    await _pumpTrack(tester, withSlot: true);

    final slotGestureDetectors = find.byWidgetPredicate((w) =>
        w is GestureDetector &&
        w.child is Stack &&
        (w.child as Stack).children.any(
            (c) => c is Positioned && c.child is MouseRegion));
    expect(slotGestureDetectors, findsWidgets,
        reason: 'timeslot rects should have gesture detectors with handle bars');

    final handles = find.byType(MouseRegion);
    final resizeHandles = handles
        .evaluate()
        .map((e) => e.widget as MouseRegion)
        .where((h) => h.cursor == SystemMouseCursors.resizeLeftRight)
        .toList();
    expect(resizeHandles, isNotEmpty,
        reason: 'handle bars should have resizeLeftRight cursor');

    final handleContainers = find.byWidgetPredicate((w) =>
        w is MouseRegion &&
        w.cursor == SystemMouseCursors.resizeLeftRight &&
        w.child is Container);
    expect(handleContainers, findsWidgets,
        reason: 'handle bars should render white containers');
  });
}

/// Pump the shared timeline track with one 60s source (+ optional timeslot).
Future<ProviderContainer> _pumpTrack(
  WidgetTester tester, {
  required bool withSlot,
  int globalPositionMs = 10000,
}) async {
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
  if (withSlot) {
    await recVm.addTimeslot(
      videoSourceId: 's1',
      inPointMs: 10000,
      outPointMs: 15000,
      filename: 'test1.mp4',
      elapse: 5000,
    );
  }

  tester.view.physicalSize = const Size(900, 200);
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
              sources: container.read(recordProvider).selectedProject!.sources,
              durationsMs: const [60000],
              previewPaths: const [null],
              globalPositionMs: globalPositionMs,
              segmentOf: (_) => 0,
              onTrackTap: (_) {},
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
  return container;
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