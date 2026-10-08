import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/data/repositories/timeslot_repository_impl.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';

void main() {
  group('RecordViewModel', () {
    late ProviderContainer container;
    late RecordViewModel vm;
    late ProjectRepositoryImpl projectRepo;
    late TimeslotRepositoryImpl timeslotRepo;
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('hlc_record_vm_test');
      // Keep autosave off the real results folder.
      AppPaths.overrideBaseDir = tmp.path;
      projectRepo = ProjectRepositoryImpl();
      timeslotRepo = TimeslotRepositoryImpl();

      container = ProviderContainer(
        overrides: [
          projectRepositoryProvider.overrideWith((ref) => projectRepo),
          timeslotRepositoryProvider.overrideWith((ref) => timeslotRepo),
          // Enable autosave for these tests (production wires 30s in main()).
          autoSaveIntervalProvider
              .overrideWithValue(const Duration(seconds: 30)),
        ],
      );
      vm = container.read(recordProvider.notifier);
      addTearDown(container.dispose);
      addTearDown(() {
        AppPaths.overrideBaseDir = null;
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
    });

    RecordState readState() =>
        container.read(recordProvider);

    test('initial state is empty', () {
      final s = readState();
      expect(s.projects, isEmpty);
      expect(s.timeslots, isEmpty);
      expect(s.selectedProjectId, isNull);
    });

    test('creates project and selects it', () async {
      await vm.createProject('My Project');
      final s = readState();
      expect(s.projects.length, 1);
      expect(s.projects.first.name, 'My Project');
      expect(s.selectedProjectId, isNotEmpty);
    });

    test('deletes project and clears selection', () async {
      await vm.createProject('To Delete');
      final id = readState().selectedProjectId!;
      await vm.deleteProject(id);
      final s = readState();
      expect(s.projects, isEmpty);
      expect(s.selectedProjectId, isNull);
    });

    test('selectProject loads timeslots', () async {
      await vm.createProject('P1');
      final pid = readState().selectedProjectId!;

      await timeslotRepo.create(Timeslot(
        id: '', projectId: pid, videoSourceId: 'v1',
        inPointMs: 0, outPointMs: 5000, createdAt: DateTime.now(),
      ));

      vm.selectProject('');
      await Future.delayed(Duration.zero);
      vm.selectProject(pid);
      await Future.delayed(Duration.zero);
      expect(readState().timeslots.length, 1);
    });

    test('mark creates a 10s window ending at the current position', () async {
      await vm.createProject('P1');
      await vm.mark(
        videoSourceId: 'v1',
        positionMs: 11000,
        filename: 'test1.mp4',
        description: 'test1_mark',
        remote: false,
      );
      expect(readState().timeslots.length, 1);
      expect(readState().timeslots.first.inPointMs, 1000);
      expect(readState().timeslots.first.outPointMs, 11000);
      expect(readState().timeslots.first.elapse, 10000);
      expect(readState().timeslots.first.description, 'test1_mark');
    });

    test('mark near video start clamps in-point to 0', () async {
      await vm.createProject('P1');
      await vm.mark(
        videoSourceId: 'v1',
        positionMs: 4000,
        filename: 'test1.mp4',
        description: 'early_mark',
        remote: false,
      );
      expect(readState().timeslots.first.inPointMs, 0);
      expect(readState().timeslots.first.outPointMs, 4000);
      expect(readState().timeslots.first.elapse, 4000);
    });

    test('undo and redo toggle availability after mark', () async {
      await vm.createProject('P');
      await vm.mark(
        videoSourceId: 'v1',
        positionMs: 5000,
        filename: 'test.mp4',
        description: 'test_mark',
        remote: false,
      );
      // After a mutation, canUndo becomes true.
      expect(readState().canUndo, true);
      expect(readState().timeslots.length, 1);

      await vm.undo();
      // Undo restores the pre-mark snapshot. canRedo becomes true.
      expect(readState().canRedo, true);
      expect(readState().canUndo, false);

      await vm.redo();
      // Redo restores the marked state.
      expect(readState().canUndo, true);
      expect(readState().canRedo, false);
    });

    test('exportTimeslotsJson produces valid JSON', () async {
      await vm.createProject('P');
      await vm.mark(
        videoSourceId: 'v1',
        positionMs: 11000,
        filename: 'test.mp4',
        description: 'test_mark',
        remote: false,
      );
      final json = vm.exportTimeslotsJson();
      expect(json.contains('11000'), true);
    });

    test('exportTimeslotsCsv produces CSV', () async {
      await vm.createProject('P');
      await vm.mark(
        videoSourceId: 'v1',
        positionMs: 11000,
        filename: 'test.mp4',
        description: 'test_mark',
        remote: false,
      );
      final csv = vm.exportTimeslotsCsv();
      expect(csv.contains('id,projectId'), true);
    });

    test('updateTimeslot modifies fields', () async {
      await vm.createProject('P');
      await vm.mark(
        videoSourceId: 'v1',
        positionMs: 5000,
        filename: 'test.mp4',
        description: 'old_desc',
        remote: false,
      );

      final slot = readState().timeslots.first;
      await vm.updateTimeslot(slot.copyWith(description: 'Goal', rating: 3));

      final updated = readState().timeslots.first;
      expect(updated.description, 'Goal');
      expect(updated.rating, 3);
    });

    test('deleteTimeslot removes the slot', () async {
      await vm.createProject('P');
      await vm.mark(
        videoSourceId: 'v1',
        positionMs: 5000,
        filename: 'test.mp4',
        description: 'to_delete',
        remote: false,
      );
      expect(readState().timeslots.length, 1);

      final id = readState().timeslots.first.id;
      await vm.deleteTimeslot(id);
      expect(readState().timeslots.length, 0);
    });

    test('updateVideoSource enriches metadata (and can skip dirty flag)',
        () async {
      await vm.createProject('P');
      final pid = readState().selectedProjectId!;
      final src = VideoSource(
        id: 's1',
        projectId: pid,
        filePath: 'C:\\Videos\\test.mp4',
        durationMs: 0,
        width: 0,
        height: 0,
        codecName: '',
        fps: 0,
        createdAt: DateTime(2024),
      );
      await vm.addVideoSource(pid, src);
      // Get back to a clean baseline: the probe write-back itself must not
      // flag the project as modified.
      vm.markSaved('C:\\x.hlcproj');
      expect(readState().isDirty, isFalse);

      await vm.updateVideoSource(
        pid,
        src.copyWith(
          durationMs: 60000,
          width: 3840,
          height: 2160,
          codecName: 'hevc',
          fps: 29.97,
        ),
        markDirty: false,
      );
      final updated = readState()
          .selectedProject!.sources.firstWhere((s) => s.id == 's1');
      expect(updated.durationMs, 60000);
      expect(updated.width, 3840);
      expect(updated.height, 2160);
      expect(updated.codecName, 'hevc');
      expect(updated.fps, closeTo(29.97, 0.001));
      expect(readState().isDirty, isFalse,
          reason: 'probe write-back should not flag the project as modified');
    });

    test('adding a source creates today\'s dated autosave project file',
        () async {
      await vm.createProject('Auto');
      final pid = readState().selectedProjectId!;

      await vm.addVideoSource(
        pid,
        VideoSource(
          id: '',
          projectId: pid,
          filePath: 'C:\\Videos\\autosave.mp4',
          durationMs: 12000,
          width: 1920,
          height: 1080,
          codecName: 'h264',
          fps: 30,
          createdAt: DateTime(2024),
        ),
      );

      final path = vm.autoSavePath;
      expect(path, isNotNull);
      expect(File(path!).existsSync(), isTrue);

      final now = DateTime.now();
      final expectedName =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}.hlcproj';
      expect(path.endsWith(expectedName), isTrue,
          reason: 'autosave file must be named after the current date');
      expect(path, startsWith(AppPaths.resultsDir));

      final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      final sources =
          (json['sources'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(sources.length, 1);
      expect(sources.first['filePath'], 'C:\\Videos\\autosave.mp4');
    });

    test('autoSaveNow persists new timeslots and clears the dirty flag',
        () async {
      await vm.createProject('Auto');
      final pid = readState().selectedProjectId!;
      await vm.addVideoSource(
        pid,
        VideoSource(
          id: '',
          projectId: pid,
          filePath: 'C:\\Videos\\a.mp4',
          durationMs: 0,
          width: 0,
          height: 0,
          codecName: '',
          fps: 0,
          createdAt: DateTime(2024),
        ),
      );
      // addVideoSource autosaves immediately, so the project starts clean.
      expect(readState().isDirty, isFalse);

      await vm.mark(
        videoSourceId: readState().selectedProject!.sources.first.id,
        positionMs: 11000,
        filename: 'a.mp4',
        description: 'goal',
        remote: false,
      );
      expect(readState().isDirty, isTrue);

      await vm.autoSaveNow();

      expect(readState().isDirty, isFalse);
      final json = jsonDecode(File(vm.autoSavePath!).readAsStringSync())
          as Map<String, dynamic>;
      final slots =
          (json['timeslots'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(slots.length, 1);
      expect(slots.first['description'], 'goal');
    });

    test('closeProject stops autosave', () async {
      await vm.createProject('Auto');
      final pid = readState().selectedProjectId!;
      await vm.addVideoSource(
        pid,
        VideoSource(
          id: '',
          projectId: pid,
          filePath: 'C:\\Videos\\a.mp4',
          durationMs: 0,
          width: 0,
          height: 0,
          codecName: '',
          fps: 0,
          createdAt: DateTime(2024),
        ),
      );
      expect(vm.autoSavePath, isNotNull);

      vm.closeProject();
      expect(vm.autoSavePath, isNull);
    });
  });
}
