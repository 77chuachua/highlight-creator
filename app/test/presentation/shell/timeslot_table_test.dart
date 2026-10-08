import 'dart:io' show Directory;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/data/repositories/timeslot_repository_impl.dart';
import 'package:highlight_creator/data/settings_service.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/presentation/shell/timeslot_table.dart';

/// Issues.md: clicking a timeslot row in the table must fire onSlotTap so the
/// host (main window / timeline) can seek + play the slot.
void main() {
  testWidgets('tapping a slot row invokes onSlotTap with that slot',
      (tester) async {
    final projectRepo = ProjectRepositoryImpl();
    final timeslotRepo = TimeslotRepositoryImpl();
    final container = ProviderContainer(
      overrides: [
        projectRepositoryProvider.overrideWith((ref) => projectRepo),
        timeslotRepositoryProvider.overrideWith((ref) => timeslotRepo),
        settingsServiceProvider.overrideWith((ref) => SettingsService(
            path:
                '${Directory.systemTemp.path}\\timeslot_table_test_settings.json')),
      ],
    );
    addTearDown(container.dispose);

    final recVm = container.read(recordProvider.notifier);
    await recVm.createProject('p1');
    await recVm.addTimeslot(
      videoSourceId: 's1',
      inPointMs: 10000,
      outPointMs: 15000,
      filename: 'test1.mp4',
      elapse: 5000,
    );

    Timeslot? tapped;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: TimeslotTable(onSlotTap: (s) => tapped = s),
            ),
          ),
        ),
      ),
    );

    final slot = container.read(recordProvider).timeslots.single;
    final rowText = find.text('Slot 1');
    expect(rowText, findsOneWidget);
    final rowInk = find.ancestor(
      of: rowText,
      matching: find.byType(InkWell),
    ).first;
    await tester.tap(rowInk);
    await tester.pump();
    expect(tapped, isNotNull, reason: 'onSlotTap must fire on row tap');
    expect(tapped!.id, slot.id);
  });

  // Issues.md: clicking a column header sorts the table by that column.
  testWidgets('clicking the Filename header sorts rows asc then desc',
      (tester) async {
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
    for (final (i, name) in [('c.mp4'), ('a.mp4'), ('b.mp4')].indexed) {
      await recVm.addTimeslot(
        videoSourceId: 's1',
        inPointMs: (i + 1) * 10000,
        outPointMs: (i + 1) * 10000 + 5000,
        filename: name,
        elapse: 5000,
      );
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: TimeslotTable(),
            ),
          ),
        ),
      ),
    );

    List<String> filenameColumn() => tester
        .widgetList<Text>(find.textContaining('.mp4'))
        .map((t) => t.data!)
        .toList(growable: false);

    expect(filenameColumn(), ['c.mp4', 'a.mp4', 'b.mp4']);

    // Tap the Filename header → ascending.
    await tester.tap(find.text('Filename'));
    await tester.pump();
    expect(filenameColumn(), ['a.mp4', 'b.mp4', 'c.mp4'],
        reason: 'first click sorts ascending');

    // Tap again → descending.
    await tester.tap(find.text('Filename'));
    await tester.pump();
    expect(filenameColumn(), ['c.mp4', 'b.mp4', 'a.mp4'],
        reason: 'second click toggles to descending');
  });

  // Issues.md: a header that is too narrow truncates the label with ellipsis
  // and offers a hover Tooltip with the full name.
  testWidgets('narrow header shows ellipsis + tooltip with full label',
      (tester) async {
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
    await recVm.addTimeslot(
      videoSourceId: 's1',
      inPointMs: 10000,
      outPointMs: 15000,
      filename: 'test1.mp4',
      elapse: 5000,
    );

    // A very narrow window forces the header cells to truncate.
    tester.view.physicalSize = const Size(360, 480);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: TimeslotTable(),
            ),
          ),
        ),
      ),
    );

    final headers = tester
        .widgetList<Tooltip>(find.byType(Tooltip))
        .where((t) => const ['Description', 'Filename', 'Timeslots'].contains(t.message))
        .toList();
    expect(headers, isNotEmpty,
        reason: 'a truncated header must expose a hover tooltip with its name');
    expect(
        tester
            .widgetList<Text>(find.byType(Text))
            .any((t) => t.data == 'Description' && t.overflow != null),
        isTrue,
        reason: 'truncated header uses ellipsis overflow');
  });
}