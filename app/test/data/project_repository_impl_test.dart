import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/repositories/project_repository_impl.dart';
import 'package:highlight_creator/domain/entities/project.dart';

/// `create` used to stamp every project with "now", which silently overrode the
/// date the loader took from the `.hlcproj` name and pushed a 2026-10-21
/// project into the current week.
void main() {
  Project project({DateTime? createdAt}) => Project(
        id: '',
        name: 'New Project',
        userId: 'local',
        createdAt: createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );

  test('keeps the date the caller passed', () async {
    final repo = ProjectRepositoryImpl();
    final created = await repo.create(project(createdAt: DateTime(2026, 10, 21)));
    expect(created.createdAt, DateTime(2026, 10, 21));
    expect(created.id, isNotEmpty);
    // The stored row must agree with what was returned.
    final stored = await repo.getById(created.id);
    expect(stored!.createdAt, DateTime(2026, 10, 21));
  });

  test('stamps "now" when no date was given', () async {
    final before = DateTime.now().subtract(const Duration(seconds: 1));
    final created = await ProjectRepositoryImpl().create(project());
    expect(created.createdAt.isAfter(before), isTrue);
  });

  test('update does not move createdAt', () async {
    final repo = ProjectRepositoryImpl();
    final created = await repo.create(project(createdAt: DateTime(2026, 10, 21)));
    final updated = await repo.update(created.copyWith(name: 'renamed'));
    expect(updated.createdAt, DateTime(2026, 10, 21));
    expect(updated.name, 'renamed');
  });
}
