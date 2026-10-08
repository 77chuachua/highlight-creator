import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/repositories/template_repository_impl.dart';
import 'package:highlight_creator/domain/entities/template.dart';

void main() {
  late Directory tempDir;
  late String storagePath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hl_tmpl_dedup_');
    storagePath = '${tempDir.path}${Platform.pathSeparator}templates.json';
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('save reuses one record per type+path instead of duplicating', () async {
    final repo = TemplateRepositoryImpl(storagePath: storagePath);

    final a = await repo.save(const Template(
      id: '',
      name: 'A',
      path: r'C:\templates\intro.mp4',
      type: TemplateType.startup,
    ));
    // Same file, different separators/case must dedupe to the same record.
    final b = await repo.save(const Template(
      id: '',
      name: 'B',
      path: r'c:/templates/intro.mp4',
      type: TemplateType.startup,
    ));

    expect(b.id, a.id, reason: 'duplicate copy of the same template created');
    final list = await repo.listByType(TemplateType.startup);
    expect(list.length, 1, reason: 'only one record should exist per template');
    expect(list.single.name, 'B', reason: 'latest save wins');
  });

  test('different type with the same path is a separate record', () async {
    final repo = TemplateRepositoryImpl(storagePath: storagePath);

    final a = await repo.save(const Template(
      id: '',
      name: 'Startup',
      path: r'C:\templates\clip.mp4',
      type: TemplateType.startup,
    ));
    final b = await repo.save(const Template(
      id: '',
      name: 'Ending',
      path: r'C:\templates\clip.mp4',
      type: TemplateType.ending,
    ));

    expect(b.id, isNot(a.id));
  });
}