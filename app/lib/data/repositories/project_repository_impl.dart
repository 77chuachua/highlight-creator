import 'package:uuid/uuid.dart';
import 'package:highlight_creator/domain/entities/project.dart';
import 'package:highlight_creator/domain/repositories/project_repository.dart';

/// In-memory implementation of ProjectRepository.
/// Phase 2: drift-backed implementation will replace this once codegen runs.
class ProjectRepositoryImpl implements ProjectRepository {
  final Map<String, Project> _projects = {};
  final Uuid _uuid = const Uuid();

  @override
  Future<Project> create(Project project) async {
    final id = project.id.isEmpty ? _uuid.v4() : project.id;
    // Keep the createdAt the caller passed: it is the project's own date (the
    // day the match was played), and the Top-5 week/month/year is derived from
    // it. Overwriting it with "now" is what kept moving a 2026-10-21 project
    // into the current week.
    final p = project.copyWith(id: id, updatedAt: DateTime.now());
    _projects[id] = p;
    return p;
  }

  @override
  Future<Project?> getById(String id) async {
    return _projects[id];
  }

  @override
  Future<Project> update(Project project) async {
    final existing = _projects[project.id];
    if (existing == null) throw StateError('Project not found: ${project.id}');
    final updated = project.copyWith(updatedAt: DateTime.now());
    _projects[project.id] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    _projects.remove(id);
  }

  @override
  Future<List<Project>> listByUser(String userId) async {
    final list = _projects.values
        .where((p) => p.userId == userId)
        .toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  @override
  Future<List<Project>> listAll() async {
    final list = _projects.values.toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }
}
