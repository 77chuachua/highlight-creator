// ignore_for_file: avoid_print
// Record the current fix batch to the SQLite database.
// Run with: dart run lib/scripts/record_fix.dart
import 'dart:io';

import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/database/database.dart';
import 'package:highlight_creator/data/repositories/fix_repository_impl.dart';
import 'package:highlight_creator/domain/entities/fix_record.dart';

Future<void> main() async {
  // Windows: database lives under %USERPROFILE%\HighlightCreator.
  final dbPath = AppPaths.databasePath;
  print('Database path: $dbPath');
  File(dbPath).parent.createSync(recursive: true);

  final db = AppDatabase.file(dbPath);
  final repo = FixRepositoryImpl(db);

  final now = DateTime.now();
  final fixes = <FixRecord>[
    FixRecord(
      id: '',
      description:
          'Track click seeks to exact point and pauses; clicking the player resumes playback',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Application window starts maximized on startup',
      filesChanged: 'main_window.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description:
          'Tracker zoom in/out buttons change the minimal time unit between 1s (zoom-in disabled) and 10s (zoom-out disabled)',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Tracker area has a horizontal scrollbar',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description:
          'Timeslot markers on the track are editable: dragging start/end edges extends or reduces elapse',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description:
          'Tracker edits update the dialog timeslot list and the main-window timeslot list together (shared record state)',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description:
          'Mark button creates a timeslot starting 10s before the current position with 10s elapse',
      filesChanged:
          'record_view_model.dart, record_view_model_test.dart, use_case_test.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Auto gen dialog maximized by default',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description:
          'Tracker background color grey, timeslot background white, video splitter bar black',
      filesChanged: 'main_window.dart, timeslot_table.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Remove Win32Window.maximize from main window startup (caused blank screen)',
      filesChanged: 'main_window.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Fix control panel play/stop bar floating center — add crossAxisAlignment.stretch to Column',
      filesChanged: 'main_window.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Revert timeslot row background to normal (remove white bg)',
      filesChanged: 'timeslot_table.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Remove Win32Window maximize/restore from auto gen dialog; keep internal _maximized state',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Auto gen dialog tracker background color grey',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Auto gen dialog track timeslot markers color white',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Track area progress fill and playhead line: change from orange to grey/white',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
    FixRecord(
      id: '',
      description: 'Timeslot markers: fallback width from outPointMs-inPointMs when elapse=0, add grey border for visual separation',
      filesChanged: 'auto_gen_dialog.dart',
      resolvedAt: now,
    ),
  ];

  for (final f in fixes) {
    final r = await repo.create(f);
    print('Recorded: ${r.id}  ${r.description}');
  }

  print('\n--- All fix records ---');
  final all = await repo.listAll();
  for (final r in all) {
    print('  [${r.resolvedAt.toIso8601String()}] ${r.description}');
    print('    Files: ${r.filesChanged}');
  }

  await db.close();
  print('\nDone. Database at: $dbPath');
}