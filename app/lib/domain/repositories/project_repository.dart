import 'package:highlight_creator/domain/entities/project.dart';

/// Abstract repository for project CRUD operations.
abstract class ProjectRepository {
  /// Create a new project.
  Future<Project> create(Project project);

  /// Get a project by ID, including timeslots and sources.
  Future<Project?> getById(String id);

  /// Update an existing project.
  Future<Project> update(Project project);

  /// Delete a project and all its associated timeslots and sources.
  Future<void> delete(String id);

  /// List all projects for a given user, ordered by last modified.
  Future<List<Project>> listByUser(String userId);

  /// List all projects (for migration / admin).
  Future<List<Project>> listAll();
}
