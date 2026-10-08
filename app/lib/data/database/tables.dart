import 'package:drift/drift.dart';

/// Table: user_profile
class UserProfiles extends Table {
  TextColumn get id => text()();
  TextColumn get displayName => text().named('display_name')();
  TextColumn get avatarPath => text().nullable().named('avatar_path')();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table: project
class Projects extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get userId => text().named('user_id').references(UserProfiles, #id)();
  DateTimeColumn get createdAt => dateTime().named('created_at')();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table: video_source
class VideoSources extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().named('project_id').references(Projects, #id)();
  TextColumn get filePath => text().named('file_path')();
  IntColumn get durationMs => integer().named('duration_ms')();
  IntColumn get width => integer()();
  IntColumn get height => integer()();
  TextColumn get codecName => text().named('codec_name')();
  RealColumn get fps => real()();
  TextColumn get thumbnailPath => text().nullable().named('thumbnail_path')();
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table: timeslot
class Timeslots extends Table {
  TextColumn get id => text()();
  TextColumn get projectId => text().named('project_id').references(Projects, #id)();
  TextColumn get videoSourceId => text().named('video_source_id').references(VideoSources, #id)();
  IntColumn get inPointMs => integer().named('in_point_ms')();
  IntColumn get outPointMs => integer().named('out_point_ms')();
  TextColumn get label => text().withDefault(const Constant(''))();
  IntColumn get colorIndex => integer().named('color_index').withDefault(const Constant(0))();
  IntColumn get rating => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().named('created_at')();

  /// New fields per issues.md structure.
  TextColumn get filename => text().withDefault(const Constant(''))();
  TextColumn get description => text().withDefault(const Constant(''))();
  IntColumn get elapse => integer().withDefault(const Constant(0))();
  BoolColumn get remote => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table: template
class Templates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get path => text().withDefault(const Constant(''))();
  TextColumn get type => text()(); // 'startup' or 'transition'

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table: fix — records completed issue fixes.
class Fixes extends Table {
  TextColumn get id => text()();
  TextColumn get description => text()(); // the issue text
  TextColumn get filesChanged => text().withDefault(const Constant(''))(); // comma-separated paths
  DateTimeColumn get resolvedAt => dateTime().named('resolved_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Table: preset
class Presets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()(); // stored as enum name string
  TextColumn get parameters => text()(); // JSON string
  BoolColumn get isBuiltIn => boolean().named('is_built_in').withDefault(const Constant(false))();
  TextColumn get userId => text().nullable().named('user_id').references(UserProfiles, #id)();
  DateTimeColumn get updatedAt => dateTime().named('updated_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
