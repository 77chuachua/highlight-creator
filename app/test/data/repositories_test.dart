import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/data/repositories/template_repository_impl.dart';
import 'package:highlight_creator/data/repositories/timeslot_repository_impl.dart';
import 'package:highlight_creator/data/database/database.dart' hide Project, Timeslot, Template, UserProfile, VideoSource, Preset;
import 'package:highlight_creator/data/repositories/fix_repository_impl.dart';
import 'package:highlight_creator/domain/entities/fix_record.dart';
import 'package:highlight_creator/domain/entities/project.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';

void main() {
  group('ProjectRepositoryImpl', () {
    late ProjectRepositoryImpl repo;

    setUp(() => repo = ProjectRepositoryImpl());

    test('create assigns an id and keeps the project date', () async {
      // createdAt is the project's own date (the match day); the Top-5 period
      // is derived from it, so create must not stamp it with "now".
      final p = await repo.create(Project(
        id: '', name: 'Test', userId: 'u1',
        createdAt: DateTime(2020), updatedAt: DateTime(2020),
      ));
      expect(p.id.isNotEmpty, true);
      expect(p.name, 'Test');
      expect(p.createdAt.year, 2020);
      expect(p.updatedAt.year, DateTime.now().year);
    });

    test('getById returns project', () async {
      final p = await repo.create(Project(
        id: '', name: 'Find Me', userId: 'u1',
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      ));
      final found = await repo.getById(p.id);
      expect(found?.name, 'Find Me');
    });

    test('getById returns null for missing', () async {
      expect(await repo.getById('nonexistent'), isNull);
    });

    test('listByUser filters by userId', () async {
      await repo.create(Project(
        id: '', name: 'A', userId: 'u1',
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      ));
      await repo.create(Project(
        id: '', name: 'B', userId: 'u2',
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      ));
      final list = await repo.listByUser('u1');
      expect(list.length, 1);
      expect(list[0].name, 'A');
    });

    test('delete removes project', () async {
      final p = await repo.create(Project(
        id: '', name: 'Del', userId: 'u1',
        createdAt: DateTime.now(), updatedAt: DateTime.now(),
      ));
      await repo.delete(p.id);
      expect(await repo.getById(p.id), isNull);
    });
  });

  group('TimeslotRepositoryImpl', () {
    late TimeslotRepositoryImpl repo;

    setUp(() => repo = TimeslotRepositoryImpl());

    test('create assigns id', () async {
      final s = await repo.create(Timeslot(
        id: '', projectId: 'p1', videoSourceId: 'v1',
        inPointMs: 0, outPointMs: 5000, createdAt: DateTime.now(),
      ));
      expect(s.id.isNotEmpty, true);
      expect(s.inPointMs, 0);
    });

    test('listByProject returns sorted', () async {
      await repo.create(Timeslot(
        id: '', projectId: 'p1', videoSourceId: 'v1',
        inPointMs: 10000, outPointMs: 15000, createdAt: DateTime.now(),
      ));
      await repo.create(Timeslot(
        id: '', projectId: 'p1', videoSourceId: 'v1',
        inPointMs: 0, outPointMs: 5000, createdAt: DateTime.now(),
      ));
      await repo.create(Timeslot(
        id: '', projectId: 'p2', videoSourceId: 'v2',
        inPointMs: 0, outPointMs: 3000, createdAt: DateTime.now(),
      ));
      final list = await repo.listByProject('p1');
      expect(list.length, 2);
      expect(list[0].inPointMs, 0);
      expect(list[1].inPointMs, 10000);
    });

    test('delete removes timeslot', () async {
      final s = await repo.create(Timeslot(
        id: '', projectId: 'p1', videoSourceId: 'v1',
        inPointMs: 0, outPointMs: 5000, createdAt: DateTime.now(),
      ));
      await repo.delete(s.id);
      expect(await repo.getById(s.id), isNull);
    });
  });

  group('TemplateRepositoryImpl', () {
    late TemplateRepositoryImpl repo;
    late Directory tempDir;

    setUp(() async {
      // Isolated registry file: the default path is the real shared user
      // registry (%USERPROFILE%\HighlightCreator\templates.json), which holds
      // accumulated user templates and must not be read or written by tests.
      tempDir = await Directory.systemTemp.createTemp('template_repo_test');
      repo = TemplateRepositoryImpl(
          storagePath: '${tempDir.path}${Platform.pathSeparator}templates.json');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('saved templates persist and are listed by the next instance',
        () async {
      await repo.save(const Template(
        id: 's1', name: 'My Startup', path: '', type: TemplateType.startup,
      ));
      await repo.save(const Template(
        id: 't1', name: 'My Transition', path: '',
        type: TemplateType.transition,
      ));
      final fresh = TemplateRepositoryImpl(
          storagePath: '${tempDir.path}${Platform.pathSeparator}templates.json');
      final all = await fresh.listAll();
      expect(all.length, 2);
      expect(all.any((t) => t.type == TemplateType.startup), isTrue);
      expect(all.any((t) => t.type == TemplateType.transition), isTrue);
    });

    test('listByType filters correctly', () async {
      await repo.save(const Template(
        id: 's1', name: 'My Startup', path: '', type: TemplateType.startup,
      ));
      await repo.save(const Template(
        id: 't1', name: 'My Transition', path: '',
        type: TemplateType.transition,
      ));
      final startups = await repo.listByType(TemplateType.startup);
      expect(startups.length, 1);
      expect(startups.first.name, 'My Startup');

      final transitions = await repo.listByType(TemplateType.transition);
      expect(transitions.length, 1);
      expect(transitions.first.name, 'My Transition');
    });

    test('save assigns id if empty', () async {
      final t = await repo.save(const Template(
        id: '', name: 'Custom', path: '', type: TemplateType.startup,
      ));
      expect(t.id.isNotEmpty, true);
      expect(t.name, 'Custom');
    });

    test('getById returns template and keeps absolute path', () async {
      final absPath =
          '${tempDir.path}${Platform.pathSeparator}my.mp4';
      final t = await repo.save(Template(
        id: 'my_startup', name: 'My Startup', path: absPath,
        type: TemplateType.startup,
      ));
      expect(t.path, absPath, reason: 'absolute paths round-trip unchanged');
      final found = await repo.getById('my_startup');
      expect(found?.name, 'My Startup');
      expect(found?.path, absPath);
    });

    test('delete removes template', () async {
      final t = await repo.save(const Template(
        id: 'to_delete', name: 'Del', path: '', type: TemplateType.transition,
      ));
      await repo.delete(t.id);
      expect(await repo.getById(t.id), isNull);
    });
  });

  group('FixRepositoryImpl', () {
    late AppDatabase db;
    late FixRepositoryImpl repo;

    setUp(() {
      db = AppDatabase.memory();
      repo = FixRepositoryImpl(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('create assigns id and returns record with same data', () async {
      final now = DateTime.now();
      final r = await repo.create(FixRecord(
        id: '', description: 'Removed open video button',
        filesChanged: 'main_window.dart',
        resolvedAt: now,
      ));
      expect(r.id.isNotEmpty, true);
      expect(r.description, 'Removed open video button');
      expect(r.filesChanged, 'main_window.dart');
      expect(r.resolvedAt, now);
    });

    test('listAll returns most recent first', () async {
      // Use explicit timestamps since SQLite resolution may not
      // distinguish timestamps created milliseconds apart.
      final older = DateTime(2024, 1, 1);
      final newer = DateTime(2025, 6, 15);
      await repo.create(FixRecord(
        id: 'a', description: 'Older fix',
        filesChanged: 'a.dart', resolvedAt: older,
      ));
      await repo.create(FixRecord(
        id: 'b', description: 'Newer fix',
        filesChanged: 'b.dart', resolvedAt: newer,
      ));
      final list = await repo.listAll();
      expect(list.length, 2);
      expect(list[0].description, 'Newer fix'); // most recent first
      expect(list[1].description, 'Older fix');
    });

    test('create preserves explicit id', () async {
      final r = await repo.create(FixRecord(
        id: 'my_id', description: 'Test',
        resolvedAt: DateTime(2020),
      ));
      expect(r.id, 'my_id');
    });
  });
}
