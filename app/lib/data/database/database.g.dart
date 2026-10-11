// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $UserProfilesTable extends UserProfiles
    with TableInfo<$UserProfilesTable, UserProfile> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserProfilesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _avatarPathMeta =
      const VerificationMeta('avatarPath');
  @override
  late final GeneratedColumn<String> avatarPath = GeneratedColumn<String>(
      'avatar_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, displayName, avatarPath, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_profiles';
  @override
  VerificationContext validateIntegrity(Insertable<UserProfile> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('avatar_path')) {
      context.handle(
          _avatarPathMeta,
          avatarPath.isAcceptableOrUnknown(
              data['avatar_path']!, _avatarPathMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  UserProfile map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return UserProfile(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      avatarPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}avatar_path']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $UserProfilesTable createAlias(String alias) {
    return $UserProfilesTable(attachedDatabase, alias);
  }
}

class UserProfile extends DataClass implements Insertable<UserProfile> {
  final String id;
  final String displayName;
  final String? avatarPath;
  final DateTime createdAt;
  final DateTime updatedAt;
  const UserProfile(
      {required this.id,
      required this.displayName,
      this.avatarPath,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || avatarPath != null) {
      map['avatar_path'] = Variable<String>(avatarPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  UserProfilesCompanion toCompanion(bool nullToAbsent) {
    return UserProfilesCompanion(
      id: Value(id),
      displayName: Value(displayName),
      avatarPath: avatarPath == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarPath),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return UserProfile(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      avatarPath: serializer.fromJson<String?>(json['avatarPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'avatarPath': serializer.toJson<String?>(avatarPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  UserProfile copyWith(
          {String? id,
          String? displayName,
          Value<String?> avatarPath = const Value.absent(),
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      UserProfile(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        avatarPath: avatarPath.present ? avatarPath.value : this.avatarPath,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  String toString() {
    return (StringBuffer('UserProfile(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, displayName, avatarPath, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is UserProfile &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.avatarPath == this.avatarPath &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class UserProfilesCompanion extends UpdateCompanion<UserProfile> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String?> avatarPath;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const UserProfilesCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.avatarPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  UserProfilesCompanion.insert({
    required String id,
    required String displayName,
    this.avatarPath = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        displayName = Value(displayName),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<UserProfile> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? avatarPath,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (avatarPath != null) 'avatar_path': avatarPath,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  UserProfilesCompanion copyWith(
      {Value<String>? id,
      Value<String>? displayName,
      Value<String?>? avatarPath,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return UserProfilesCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      avatarPath: avatarPath ?? this.avatarPath,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (avatarPath.present) {
      map['avatar_path'] = Variable<String>(avatarPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserProfilesCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('avatarPath: $avatarPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProjectsTable extends Projects with TableInfo<$ProjectsTable, Project> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProjectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES user_profiles (id)'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, userId, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'projects';
  @override
  VerificationContext validateIntegrity(Insertable<Project> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Project map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Project(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $ProjectsTable createAlias(String alias) {
    return $ProjectsTable(attachedDatabase, alias);
  }
}

class Project extends DataClass implements Insertable<Project> {
  final String id;
  final String name;
  final String userId;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Project(
      {required this.id,
      required this.name,
      required this.userId,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['user_id'] = Variable<String>(userId);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  ProjectsCompanion toCompanion(bool nullToAbsent) {
    return ProjectsCompanion(
      id: Value(id),
      name: Value(name),
      userId: Value(userId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Project.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Project(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      userId: serializer.fromJson<String>(json['userId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'userId': serializer.toJson<String>(userId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Project copyWith(
          {String? id,
          String? name,
          String? userId,
          DateTime? createdAt,
          DateTime? updatedAt}) =>
      Project(
        id: id ?? this.id,
        name: name ?? this.name,
        userId: userId ?? this.userId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  String toString() {
    return (StringBuffer('Project(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('userId: $userId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, userId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Project &&
          other.id == this.id &&
          other.name == this.name &&
          other.userId == this.userId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class ProjectsCompanion extends UpdateCompanion<Project> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> userId;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const ProjectsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.userId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProjectsCompanion.insert({
    required String id,
    required String name,
    required String userId,
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        userId = Value(userId),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<Project> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? userId,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (userId != null) 'user_id': userId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProjectsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? userId,
      Value<DateTime>? createdAt,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return ProjectsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      userId: userId ?? this.userId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProjectsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('userId: $userId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $VideoSourcesTable extends VideoSources
    with TableInfo<$VideoSourcesTable, VideoSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VideoSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _projectIdMeta =
      const VerificationMeta('projectId');
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
      'project_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES projects (id)'));
  static const VerificationMeta _filePathMeta =
      const VerificationMeta('filePath');
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
      'file_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
      'width', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
      'height', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _codecNameMeta =
      const VerificationMeta('codecName');
  @override
  late final GeneratedColumn<String> codecName = GeneratedColumn<String>(
      'codec_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fpsMeta = const VerificationMeta('fps');
  @override
  late final GeneratedColumn<double> fps = GeneratedColumn<double>(
      'fps', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _thumbnailPathMeta =
      const VerificationMeta('thumbnailPath');
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
      'thumbnail_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        projectId,
        filePath,
        durationMs,
        width,
        height,
        codecName,
        fps,
        thumbnailPath,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'video_sources';
  @override
  VerificationContext validateIntegrity(Insertable<VideoSource> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(_projectIdMeta,
          projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta));
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('file_path')) {
      context.handle(_filePathMeta,
          filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta));
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    } else if (isInserting) {
      context.missing(_durationMsMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
          _widthMeta, width.isAcceptableOrUnknown(data['width']!, _widthMeta));
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('height')) {
      context.handle(_heightMeta,
          height.isAcceptableOrUnknown(data['height']!, _heightMeta));
    } else if (isInserting) {
      context.missing(_heightMeta);
    }
    if (data.containsKey('codec_name')) {
      context.handle(_codecNameMeta,
          codecName.isAcceptableOrUnknown(data['codec_name']!, _codecNameMeta));
    } else if (isInserting) {
      context.missing(_codecNameMeta);
    }
    if (data.containsKey('fps')) {
      context.handle(
          _fpsMeta, fps.isAcceptableOrUnknown(data['fps']!, _fpsMeta));
    } else if (isInserting) {
      context.missing(_fpsMeta);
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
          _thumbnailPathMeta,
          thumbnailPath.isAcceptableOrUnknown(
              data['thumbnail_path']!, _thumbnailPathMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  VideoSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VideoSource(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      projectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}project_id'])!,
      filePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_path'])!,
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms'])!,
      width: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}width'])!,
      height: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}height'])!,
      codecName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}codec_name'])!,
      fps: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}fps'])!,
      thumbnailPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_path']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $VideoSourcesTable createAlias(String alias) {
    return $VideoSourcesTable(attachedDatabase, alias);
  }
}

class VideoSource extends DataClass implements Insertable<VideoSource> {
  final String id;
  final String projectId;
  final String filePath;
  final int durationMs;
  final int width;
  final int height;
  final String codecName;
  final double fps;
  final String? thumbnailPath;
  final DateTime createdAt;
  const VideoSource(
      {required this.id,
      required this.projectId,
      required this.filePath,
      required this.durationMs,
      required this.width,
      required this.height,
      required this.codecName,
      required this.fps,
      this.thumbnailPath,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['file_path'] = Variable<String>(filePath);
    map['duration_ms'] = Variable<int>(durationMs);
    map['width'] = Variable<int>(width);
    map['height'] = Variable<int>(height);
    map['codec_name'] = Variable<String>(codecName);
    map['fps'] = Variable<double>(fps);
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  VideoSourcesCompanion toCompanion(bool nullToAbsent) {
    return VideoSourcesCompanion(
      id: Value(id),
      projectId: Value(projectId),
      filePath: Value(filePath),
      durationMs: Value(durationMs),
      width: Value(width),
      height: Value(height),
      codecName: Value(codecName),
      fps: Value(fps),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      createdAt: Value(createdAt),
    );
  }

  factory VideoSource.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VideoSource(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      filePath: serializer.fromJson<String>(json['filePath']),
      durationMs: serializer.fromJson<int>(json['durationMs']),
      width: serializer.fromJson<int>(json['width']),
      height: serializer.fromJson<int>(json['height']),
      codecName: serializer.fromJson<String>(json['codecName']),
      fps: serializer.fromJson<double>(json['fps']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'filePath': serializer.toJson<String>(filePath),
      'durationMs': serializer.toJson<int>(durationMs),
      'width': serializer.toJson<int>(width),
      'height': serializer.toJson<int>(height),
      'codecName': serializer.toJson<String>(codecName),
      'fps': serializer.toJson<double>(fps),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  VideoSource copyWith(
          {String? id,
          String? projectId,
          String? filePath,
          int? durationMs,
          int? width,
          int? height,
          String? codecName,
          double? fps,
          Value<String?> thumbnailPath = const Value.absent(),
          DateTime? createdAt}) =>
      VideoSource(
        id: id ?? this.id,
        projectId: projectId ?? this.projectId,
        filePath: filePath ?? this.filePath,
        durationMs: durationMs ?? this.durationMs,
        width: width ?? this.width,
        height: height ?? this.height,
        codecName: codecName ?? this.codecName,
        fps: fps ?? this.fps,
        thumbnailPath:
            thumbnailPath.present ? thumbnailPath.value : this.thumbnailPath,
        createdAt: createdAt ?? this.createdAt,
      );
  @override
  String toString() {
    return (StringBuffer('VideoSource(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('filePath: $filePath, ')
          ..write('durationMs: $durationMs, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('codecName: $codecName, ')
          ..write('fps: $fps, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, projectId, filePath, durationMs, width,
      height, codecName, fps, thumbnailPath, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VideoSource &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.filePath == this.filePath &&
          other.durationMs == this.durationMs &&
          other.width == this.width &&
          other.height == this.height &&
          other.codecName == this.codecName &&
          other.fps == this.fps &&
          other.thumbnailPath == this.thumbnailPath &&
          other.createdAt == this.createdAt);
}

class VideoSourcesCompanion extends UpdateCompanion<VideoSource> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String> filePath;
  final Value<int> durationMs;
  final Value<int> width;
  final Value<int> height;
  final Value<String> codecName;
  final Value<double> fps;
  final Value<String?> thumbnailPath;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const VideoSourcesCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.filePath = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.codecName = const Value.absent(),
    this.fps = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VideoSourcesCompanion.insert({
    required String id,
    required String projectId,
    required String filePath,
    required int durationMs,
    required int width,
    required int height,
    required String codecName,
    required double fps,
    this.thumbnailPath = const Value.absent(),
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        projectId = Value(projectId),
        filePath = Value(filePath),
        durationMs = Value(durationMs),
        width = Value(width),
        height = Value(height),
        codecName = Value(codecName),
        fps = Value(fps),
        createdAt = Value(createdAt);
  static Insertable<VideoSource> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? filePath,
    Expression<int>? durationMs,
    Expression<int>? width,
    Expression<int>? height,
    Expression<String>? codecName,
    Expression<double>? fps,
    Expression<String>? thumbnailPath,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (filePath != null) 'file_path': filePath,
      if (durationMs != null) 'duration_ms': durationMs,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (codecName != null) 'codec_name': codecName,
      if (fps != null) 'fps': fps,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VideoSourcesCompanion copyWith(
      {Value<String>? id,
      Value<String>? projectId,
      Value<String>? filePath,
      Value<int>? durationMs,
      Value<int>? width,
      Value<int>? height,
      Value<String>? codecName,
      Value<double>? fps,
      Value<String?>? thumbnailPath,
      Value<DateTime>? createdAt,
      Value<int>? rowid}) {
    return VideoSourcesCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      width: width ?? this.width,
      height: height ?? this.height,
      codecName: codecName ?? this.codecName,
      fps: fps ?? this.fps,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (codecName.present) {
      map['codec_name'] = Variable<String>(codecName.value);
    }
    if (fps.present) {
      map['fps'] = Variable<double>(fps.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VideoSourcesCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('filePath: $filePath, ')
          ..write('durationMs: $durationMs, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('codecName: $codecName, ')
          ..write('fps: $fps, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TimeslotsTable extends Timeslots
    with TableInfo<$TimeslotsTable, Timeslot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimeslotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _projectIdMeta =
      const VerificationMeta('projectId');
  @override
  late final GeneratedColumn<String> projectId = GeneratedColumn<String>(
      'project_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES projects (id)'));
  static const VerificationMeta _videoSourceIdMeta =
      const VerificationMeta('videoSourceId');
  @override
  late final GeneratedColumn<String> videoSourceId = GeneratedColumn<String>(
      'video_source_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES video_sources (id)'));
  static const VerificationMeta _inPointMsMeta =
      const VerificationMeta('inPointMs');
  @override
  late final GeneratedColumn<int> inPointMs = GeneratedColumn<int>(
      'in_point_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _outPointMsMeta =
      const VerificationMeta('outPointMs');
  @override
  late final GeneratedColumn<int> outPointMs = GeneratedColumn<int>(
      'out_point_ms', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
      'label', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _colorIndexMeta =
      const VerificationMeta('colorIndex');
  @override
  late final GeneratedColumn<int> colorIndex = GeneratedColumn<int>(
      'color_index', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
      'rating', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _filenameMeta =
      const VerificationMeta('filename');
  @override
  late final GeneratedColumn<String> filename = GeneratedColumn<String>(
      'filename', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _elapseMeta = const VerificationMeta('elapse');
  @override
  late final GeneratedColumn<int> elapse = GeneratedColumn<int>(
      'elapse', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _remoteMeta = const VerificationMeta('remote');
  @override
  late final GeneratedColumn<bool> remote = GeneratedColumn<bool>(
      'remote', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("remote" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        projectId,
        videoSourceId,
        inPointMs,
        outPointMs,
        label,
        colorIndex,
        rating,
        createdAt,
        filename,
        description,
        elapse,
        remote
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'timeslots';
  @override
  VerificationContext validateIntegrity(Insertable<Timeslot> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('project_id')) {
      context.handle(_projectIdMeta,
          projectId.isAcceptableOrUnknown(data['project_id']!, _projectIdMeta));
    } else if (isInserting) {
      context.missing(_projectIdMeta);
    }
    if (data.containsKey('video_source_id')) {
      context.handle(
          _videoSourceIdMeta,
          videoSourceId.isAcceptableOrUnknown(
              data['video_source_id']!, _videoSourceIdMeta));
    } else if (isInserting) {
      context.missing(_videoSourceIdMeta);
    }
    if (data.containsKey('in_point_ms')) {
      context.handle(
          _inPointMsMeta,
          inPointMs.isAcceptableOrUnknown(
              data['in_point_ms']!, _inPointMsMeta));
    } else if (isInserting) {
      context.missing(_inPointMsMeta);
    }
    if (data.containsKey('out_point_ms')) {
      context.handle(
          _outPointMsMeta,
          outPointMs.isAcceptableOrUnknown(
              data['out_point_ms']!, _outPointMsMeta));
    } else if (isInserting) {
      context.missing(_outPointMsMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
          _labelMeta, label.isAcceptableOrUnknown(data['label']!, _labelMeta));
    }
    if (data.containsKey('color_index')) {
      context.handle(
          _colorIndexMeta,
          colorIndex.isAcceptableOrUnknown(
              data['color_index']!, _colorIndexMeta));
    }
    if (data.containsKey('rating')) {
      context.handle(_ratingMeta,
          rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('filename')) {
      context.handle(_filenameMeta,
          filename.isAcceptableOrUnknown(data['filename']!, _filenameMeta));
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    }
    if (data.containsKey('elapse')) {
      context.handle(_elapseMeta,
          elapse.isAcceptableOrUnknown(data['elapse']!, _elapseMeta));
    }
    if (data.containsKey('remote')) {
      context.handle(_remoteMeta,
          remote.isAcceptableOrUnknown(data['remote']!, _remoteMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Timeslot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Timeslot(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      projectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}project_id'])!,
      videoSourceId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}video_source_id'])!,
      inPointMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}in_point_ms'])!,
      outPointMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}out_point_ms'])!,
      label: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}label'])!,
      colorIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}color_index'])!,
      rating: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rating'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      filename: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}filename'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      elapse: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}elapse'])!,
      remote: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}remote'])!,
    );
  }

  @override
  $TimeslotsTable createAlias(String alias) {
    return $TimeslotsTable(attachedDatabase, alias);
  }
}

class Timeslot extends DataClass implements Insertable<Timeslot> {
  final String id;
  final String projectId;
  final String videoSourceId;
  final int inPointMs;
  final int outPointMs;
  final String label;
  final int colorIndex;
  final int rating;
  final DateTime createdAt;

  /// New fields per issues.md structure.
  final String filename;
  final String description;
  final int elapse;
  final bool remote;
  const Timeslot(
      {required this.id,
      required this.projectId,
      required this.videoSourceId,
      required this.inPointMs,
      required this.outPointMs,
      required this.label,
      required this.colorIndex,
      required this.rating,
      required this.createdAt,
      required this.filename,
      required this.description,
      required this.elapse,
      required this.remote});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['project_id'] = Variable<String>(projectId);
    map['video_source_id'] = Variable<String>(videoSourceId);
    map['in_point_ms'] = Variable<int>(inPointMs);
    map['out_point_ms'] = Variable<int>(outPointMs);
    map['label'] = Variable<String>(label);
    map['color_index'] = Variable<int>(colorIndex);
    map['rating'] = Variable<int>(rating);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['filename'] = Variable<String>(filename);
    map['description'] = Variable<String>(description);
    map['elapse'] = Variable<int>(elapse);
    map['remote'] = Variable<bool>(remote);
    return map;
  }

  TimeslotsCompanion toCompanion(bool nullToAbsent) {
    return TimeslotsCompanion(
      id: Value(id),
      projectId: Value(projectId),
      videoSourceId: Value(videoSourceId),
      inPointMs: Value(inPointMs),
      outPointMs: Value(outPointMs),
      label: Value(label),
      colorIndex: Value(colorIndex),
      rating: Value(rating),
      createdAt: Value(createdAt),
      filename: Value(filename),
      description: Value(description),
      elapse: Value(elapse),
      remote: Value(remote),
    );
  }

  factory Timeslot.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Timeslot(
      id: serializer.fromJson<String>(json['id']),
      projectId: serializer.fromJson<String>(json['projectId']),
      videoSourceId: serializer.fromJson<String>(json['videoSourceId']),
      inPointMs: serializer.fromJson<int>(json['inPointMs']),
      outPointMs: serializer.fromJson<int>(json['outPointMs']),
      label: serializer.fromJson<String>(json['label']),
      colorIndex: serializer.fromJson<int>(json['colorIndex']),
      rating: serializer.fromJson<int>(json['rating']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      filename: serializer.fromJson<String>(json['filename']),
      description: serializer.fromJson<String>(json['description']),
      elapse: serializer.fromJson<int>(json['elapse']),
      remote: serializer.fromJson<bool>(json['remote']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'projectId': serializer.toJson<String>(projectId),
      'videoSourceId': serializer.toJson<String>(videoSourceId),
      'inPointMs': serializer.toJson<int>(inPointMs),
      'outPointMs': serializer.toJson<int>(outPointMs),
      'label': serializer.toJson<String>(label),
      'colorIndex': serializer.toJson<int>(colorIndex),
      'rating': serializer.toJson<int>(rating),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'filename': serializer.toJson<String>(filename),
      'description': serializer.toJson<String>(description),
      'elapse': serializer.toJson<int>(elapse),
      'remote': serializer.toJson<bool>(remote),
    };
  }

  Timeslot copyWith(
          {String? id,
          String? projectId,
          String? videoSourceId,
          int? inPointMs,
          int? outPointMs,
          String? label,
          int? colorIndex,
          int? rating,
          DateTime? createdAt,
          String? filename,
          String? description,
          int? elapse,
          bool? remote}) =>
      Timeslot(
        id: id ?? this.id,
        projectId: projectId ?? this.projectId,
        videoSourceId: videoSourceId ?? this.videoSourceId,
        inPointMs: inPointMs ?? this.inPointMs,
        outPointMs: outPointMs ?? this.outPointMs,
        label: label ?? this.label,
        colorIndex: colorIndex ?? this.colorIndex,
        rating: rating ?? this.rating,
        createdAt: createdAt ?? this.createdAt,
        filename: filename ?? this.filename,
        description: description ?? this.description,
        elapse: elapse ?? this.elapse,
        remote: remote ?? this.remote,
      );
  @override
  String toString() {
    return (StringBuffer('Timeslot(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('videoSourceId: $videoSourceId, ')
          ..write('inPointMs: $inPointMs, ')
          ..write('outPointMs: $outPointMs, ')
          ..write('label: $label, ')
          ..write('colorIndex: $colorIndex, ')
          ..write('rating: $rating, ')
          ..write('createdAt: $createdAt, ')
          ..write('filename: $filename, ')
          ..write('description: $description, ')
          ..write('elapse: $elapse, ')
          ..write('remote: $remote')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      projectId,
      videoSourceId,
      inPointMs,
      outPointMs,
      label,
      colorIndex,
      rating,
      createdAt,
      filename,
      description,
      elapse,
      remote);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Timeslot &&
          other.id == this.id &&
          other.projectId == this.projectId &&
          other.videoSourceId == this.videoSourceId &&
          other.inPointMs == this.inPointMs &&
          other.outPointMs == this.outPointMs &&
          other.label == this.label &&
          other.colorIndex == this.colorIndex &&
          other.rating == this.rating &&
          other.createdAt == this.createdAt &&
          other.filename == this.filename &&
          other.description == this.description &&
          other.elapse == this.elapse &&
          other.remote == this.remote);
}

class TimeslotsCompanion extends UpdateCompanion<Timeslot> {
  final Value<String> id;
  final Value<String> projectId;
  final Value<String> videoSourceId;
  final Value<int> inPointMs;
  final Value<int> outPointMs;
  final Value<String> label;
  final Value<int> colorIndex;
  final Value<int> rating;
  final Value<DateTime> createdAt;
  final Value<String> filename;
  final Value<String> description;
  final Value<int> elapse;
  final Value<bool> remote;
  final Value<int> rowid;
  const TimeslotsCompanion({
    this.id = const Value.absent(),
    this.projectId = const Value.absent(),
    this.videoSourceId = const Value.absent(),
    this.inPointMs = const Value.absent(),
    this.outPointMs = const Value.absent(),
    this.label = const Value.absent(),
    this.colorIndex = const Value.absent(),
    this.rating = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.filename = const Value.absent(),
    this.description = const Value.absent(),
    this.elapse = const Value.absent(),
    this.remote = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TimeslotsCompanion.insert({
    required String id,
    required String projectId,
    required String videoSourceId,
    required int inPointMs,
    required int outPointMs,
    this.label = const Value.absent(),
    this.colorIndex = const Value.absent(),
    this.rating = const Value.absent(),
    required DateTime createdAt,
    this.filename = const Value.absent(),
    this.description = const Value.absent(),
    this.elapse = const Value.absent(),
    this.remote = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        projectId = Value(projectId),
        videoSourceId = Value(videoSourceId),
        inPointMs = Value(inPointMs),
        outPointMs = Value(outPointMs),
        createdAt = Value(createdAt);
  static Insertable<Timeslot> custom({
    Expression<String>? id,
    Expression<String>? projectId,
    Expression<String>? videoSourceId,
    Expression<int>? inPointMs,
    Expression<int>? outPointMs,
    Expression<String>? label,
    Expression<int>? colorIndex,
    Expression<int>? rating,
    Expression<DateTime>? createdAt,
    Expression<String>? filename,
    Expression<String>? description,
    Expression<int>? elapse,
    Expression<bool>? remote,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (projectId != null) 'project_id': projectId,
      if (videoSourceId != null) 'video_source_id': videoSourceId,
      if (inPointMs != null) 'in_point_ms': inPointMs,
      if (outPointMs != null) 'out_point_ms': outPointMs,
      if (label != null) 'label': label,
      if (colorIndex != null) 'color_index': colorIndex,
      if (rating != null) 'rating': rating,
      if (createdAt != null) 'created_at': createdAt,
      if (filename != null) 'filename': filename,
      if (description != null) 'description': description,
      if (elapse != null) 'elapse': elapse,
      if (remote != null) 'remote': remote,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TimeslotsCompanion copyWith(
      {Value<String>? id,
      Value<String>? projectId,
      Value<String>? videoSourceId,
      Value<int>? inPointMs,
      Value<int>? outPointMs,
      Value<String>? label,
      Value<int>? colorIndex,
      Value<int>? rating,
      Value<DateTime>? createdAt,
      Value<String>? filename,
      Value<String>? description,
      Value<int>? elapse,
      Value<bool>? remote,
      Value<int>? rowid}) {
    return TimeslotsCompanion(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      videoSourceId: videoSourceId ?? this.videoSourceId,
      inPointMs: inPointMs ?? this.inPointMs,
      outPointMs: outPointMs ?? this.outPointMs,
      label: label ?? this.label,
      colorIndex: colorIndex ?? this.colorIndex,
      rating: rating ?? this.rating,
      createdAt: createdAt ?? this.createdAt,
      filename: filename ?? this.filename,
      description: description ?? this.description,
      elapse: elapse ?? this.elapse,
      remote: remote ?? this.remote,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (projectId.present) {
      map['project_id'] = Variable<String>(projectId.value);
    }
    if (videoSourceId.present) {
      map['video_source_id'] = Variable<String>(videoSourceId.value);
    }
    if (inPointMs.present) {
      map['in_point_ms'] = Variable<int>(inPointMs.value);
    }
    if (outPointMs.present) {
      map['out_point_ms'] = Variable<int>(outPointMs.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (colorIndex.present) {
      map['color_index'] = Variable<int>(colorIndex.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (filename.present) {
      map['filename'] = Variable<String>(filename.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (elapse.present) {
      map['elapse'] = Variable<int>(elapse.value);
    }
    if (remote.present) {
      map['remote'] = Variable<bool>(remote.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TimeslotsCompanion(')
          ..write('id: $id, ')
          ..write('projectId: $projectId, ')
          ..write('videoSourceId: $videoSourceId, ')
          ..write('inPointMs: $inPointMs, ')
          ..write('outPointMs: $outPointMs, ')
          ..write('label: $label, ')
          ..write('colorIndex: $colorIndex, ')
          ..write('rating: $rating, ')
          ..write('createdAt: $createdAt, ')
          ..write('filename: $filename, ')
          ..write('description: $description, ')
          ..write('elapse: $elapse, ')
          ..write('remote: $remote, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TemplatesTable extends Templates
    with TableInfo<$TemplatesTable, Template> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TemplatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
      'path', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
      'type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, name, path, type];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'templates';
  @override
  VerificationContext validateIntegrity(Insertable<Template> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
          _pathMeta, path.isAcceptableOrUnknown(data['path']!, _pathMeta));
    }
    if (data.containsKey('type')) {
      context.handle(
          _typeMeta, type.isAcceptableOrUnknown(data['type']!, _typeMeta));
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Template map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Template(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      path: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}path'])!,
      type: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}type'])!,
    );
  }

  @override
  $TemplatesTable createAlias(String alias) {
    return $TemplatesTable(attachedDatabase, alias);
  }
}

class Template extends DataClass implements Insertable<Template> {
  final String id;
  final String name;
  final String path;
  final String type;
  const Template(
      {required this.id,
      required this.name,
      required this.path,
      required this.type});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['path'] = Variable<String>(path);
    map['type'] = Variable<String>(type);
    return map;
  }

  TemplatesCompanion toCompanion(bool nullToAbsent) {
    return TemplatesCompanion(
      id: Value(id),
      name: Value(name),
      path: Value(path),
      type: Value(type),
    );
  }

  factory Template.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Template(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      path: serializer.fromJson<String>(json['path']),
      type: serializer.fromJson<String>(json['type']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'path': serializer.toJson<String>(path),
      'type': serializer.toJson<String>(type),
    };
  }

  Template copyWith({String? id, String? name, String? path, String? type}) =>
      Template(
        id: id ?? this.id,
        name: name ?? this.name,
        path: path ?? this.path,
        type: type ?? this.type,
      );
  @override
  String toString() {
    return (StringBuffer('Template(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('path: $path, ')
          ..write('type: $type')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, path, type);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Template &&
          other.id == this.id &&
          other.name == this.name &&
          other.path == this.path &&
          other.type == this.type);
}

class TemplatesCompanion extends UpdateCompanion<Template> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> path;
  final Value<String> type;
  final Value<int> rowid;
  const TemplatesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.path = const Value.absent(),
    this.type = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TemplatesCompanion.insert({
    required String id,
    required String name,
    this.path = const Value.absent(),
    required String type,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        type = Value(type);
  static Insertable<Template> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? path,
    Expression<String>? type,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (path != null) 'path': path,
      if (type != null) 'type': type,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TemplatesCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? path,
      Value<String>? type,
      Value<int>? rowid}) {
    return TemplatesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      type: type ?? this.type,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TemplatesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('path: $path, ')
          ..write('type: $type, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FixesTable extends Fixes with TableInfo<$FixesTable, Fixe> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FixesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _descriptionMeta =
      const VerificationMeta('description');
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
      'description', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _filesChangedMeta =
      const VerificationMeta('filesChanged');
  @override
  late final GeneratedColumn<String> filesChanged = GeneratedColumn<String>(
      'files_changed', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant(''));
  static const VerificationMeta _resolvedAtMeta =
      const VerificationMeta('resolvedAt');
  @override
  late final GeneratedColumn<DateTime> resolvedAt = GeneratedColumn<DateTime>(
      'resolved_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, description, filesChanged, resolvedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fixes';
  @override
  VerificationContext validateIntegrity(Insertable<Fixe> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
          _descriptionMeta,
          description.isAcceptableOrUnknown(
              data['description']!, _descriptionMeta));
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('files_changed')) {
      context.handle(
          _filesChangedMeta,
          filesChanged.isAcceptableOrUnknown(
              data['files_changed']!, _filesChangedMeta));
    }
    if (data.containsKey('resolved_at')) {
      context.handle(
          _resolvedAtMeta,
          resolvedAt.isAcceptableOrUnknown(
              data['resolved_at']!, _resolvedAtMeta));
    } else if (isInserting) {
      context.missing(_resolvedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Fixe map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Fixe(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      description: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}description'])!,
      filesChanged: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}files_changed'])!,
      resolvedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}resolved_at'])!,
    );
  }

  @override
  $FixesTable createAlias(String alias) {
    return $FixesTable(attachedDatabase, alias);
  }
}

class Fixe extends DataClass implements Insertable<Fixe> {
  final String id;
  final String description;
  final String filesChanged;
  final DateTime resolvedAt;
  const Fixe(
      {required this.id,
      required this.description,
      required this.filesChanged,
      required this.resolvedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['description'] = Variable<String>(description);
    map['files_changed'] = Variable<String>(filesChanged);
    map['resolved_at'] = Variable<DateTime>(resolvedAt);
    return map;
  }

  FixesCompanion toCompanion(bool nullToAbsent) {
    return FixesCompanion(
      id: Value(id),
      description: Value(description),
      filesChanged: Value(filesChanged),
      resolvedAt: Value(resolvedAt),
    );
  }

  factory Fixe.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Fixe(
      id: serializer.fromJson<String>(json['id']),
      description: serializer.fromJson<String>(json['description']),
      filesChanged: serializer.fromJson<String>(json['filesChanged']),
      resolvedAt: serializer.fromJson<DateTime>(json['resolvedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'description': serializer.toJson<String>(description),
      'filesChanged': serializer.toJson<String>(filesChanged),
      'resolvedAt': serializer.toJson<DateTime>(resolvedAt),
    };
  }

  Fixe copyWith(
          {String? id,
          String? description,
          String? filesChanged,
          DateTime? resolvedAt}) =>
      Fixe(
        id: id ?? this.id,
        description: description ?? this.description,
        filesChanged: filesChanged ?? this.filesChanged,
        resolvedAt: resolvedAt ?? this.resolvedAt,
      );
  @override
  String toString() {
    return (StringBuffer('Fixe(')
          ..write('id: $id, ')
          ..write('description: $description, ')
          ..write('filesChanged: $filesChanged, ')
          ..write('resolvedAt: $resolvedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, description, filesChanged, resolvedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Fixe &&
          other.id == this.id &&
          other.description == this.description &&
          other.filesChanged == this.filesChanged &&
          other.resolvedAt == this.resolvedAt);
}

class FixesCompanion extends UpdateCompanion<Fixe> {
  final Value<String> id;
  final Value<String> description;
  final Value<String> filesChanged;
  final Value<DateTime> resolvedAt;
  final Value<int> rowid;
  const FixesCompanion({
    this.id = const Value.absent(),
    this.description = const Value.absent(),
    this.filesChanged = const Value.absent(),
    this.resolvedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FixesCompanion.insert({
    required String id,
    required String description,
    this.filesChanged = const Value.absent(),
    required DateTime resolvedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        description = Value(description),
        resolvedAt = Value(resolvedAt);
  static Insertable<Fixe> custom({
    Expression<String>? id,
    Expression<String>? description,
    Expression<String>? filesChanged,
    Expression<DateTime>? resolvedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (description != null) 'description': description,
      if (filesChanged != null) 'files_changed': filesChanged,
      if (resolvedAt != null) 'resolved_at': resolvedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FixesCompanion copyWith(
      {Value<String>? id,
      Value<String>? description,
      Value<String>? filesChanged,
      Value<DateTime>? resolvedAt,
      Value<int>? rowid}) {
    return FixesCompanion(
      id: id ?? this.id,
      description: description ?? this.description,
      filesChanged: filesChanged ?? this.filesChanged,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (filesChanged.present) {
      map['files_changed'] = Variable<String>(filesChanged.value);
    }
    if (resolvedAt.present) {
      map['resolved_at'] = Variable<DateTime>(resolvedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FixesCompanion(')
          ..write('id: $id, ')
          ..write('description: $description, ')
          ..write('filesChanged: $filesChanged, ')
          ..write('resolvedAt: $resolvedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PresetsTable extends Presets with TableInfo<$PresetsTable, Preset> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PresetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _categoryMeta =
      const VerificationMeta('category');
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
      'category', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _parametersMeta =
      const VerificationMeta('parameters');
  @override
  late final GeneratedColumn<String> parameters = GeneratedColumn<String>(
      'parameters', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isBuiltInMeta =
      const VerificationMeta('isBuiltIn');
  @override
  late final GeneratedColumn<bool> isBuiltIn = GeneratedColumn<bool>(
      'is_built_in', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_built_in" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES user_profiles (id)'));
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, name, category, parameters, isBuiltIn, userId, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'presets';
  @override
  VerificationContext validateIntegrity(Insertable<Preset> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('category')) {
      context.handle(_categoryMeta,
          category.isAcceptableOrUnknown(data['category']!, _categoryMeta));
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('parameters')) {
      context.handle(
          _parametersMeta,
          parameters.isAcceptableOrUnknown(
              data['parameters']!, _parametersMeta));
    } else if (isInserting) {
      context.missing(_parametersMeta);
    }
    if (data.containsKey('is_built_in')) {
      context.handle(
          _isBuiltInMeta,
          isBuiltIn.isAcceptableOrUnknown(
              data['is_built_in']!, _isBuiltInMeta));
    }
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Preset map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Preset(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      category: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}category'])!,
      parameters: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parameters'])!,
      isBuiltIn: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_built_in'])!,
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $PresetsTable createAlias(String alias) {
    return $PresetsTable(attachedDatabase, alias);
  }
}

class Preset extends DataClass implements Insertable<Preset> {
  final String id;
  final String name;
  final String category;
  final String parameters;
  final bool isBuiltIn;
  final String? userId;
  final DateTime updatedAt;
  const Preset(
      {required this.id,
      required this.name,
      required this.category,
      required this.parameters,
      required this.isBuiltIn,
      this.userId,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['category'] = Variable<String>(category);
    map['parameters'] = Variable<String>(parameters);
    map['is_built_in'] = Variable<bool>(isBuiltIn);
    if (!nullToAbsent || userId != null) {
      map['user_id'] = Variable<String>(userId);
    }
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  PresetsCompanion toCompanion(bool nullToAbsent) {
    return PresetsCompanion(
      id: Value(id),
      name: Value(name),
      category: Value(category),
      parameters: Value(parameters),
      isBuiltIn: Value(isBuiltIn),
      userId:
          userId == null && nullToAbsent ? const Value.absent() : Value(userId),
      updatedAt: Value(updatedAt),
    );
  }

  factory Preset.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Preset(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      category: serializer.fromJson<String>(json['category']),
      parameters: serializer.fromJson<String>(json['parameters']),
      isBuiltIn: serializer.fromJson<bool>(json['isBuiltIn']),
      userId: serializer.fromJson<String?>(json['userId']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'category': serializer.toJson<String>(category),
      'parameters': serializer.toJson<String>(parameters),
      'isBuiltIn': serializer.toJson<bool>(isBuiltIn),
      'userId': serializer.toJson<String?>(userId),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Preset copyWith(
          {String? id,
          String? name,
          String? category,
          String? parameters,
          bool? isBuiltIn,
          Value<String?> userId = const Value.absent(),
          DateTime? updatedAt}) =>
      Preset(
        id: id ?? this.id,
        name: name ?? this.name,
        category: category ?? this.category,
        parameters: parameters ?? this.parameters,
        isBuiltIn: isBuiltIn ?? this.isBuiltIn,
        userId: userId.present ? userId.value : this.userId,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  @override
  String toString() {
    return (StringBuffer('Preset(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('parameters: $parameters, ')
          ..write('isBuiltIn: $isBuiltIn, ')
          ..write('userId: $userId, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, category, parameters, isBuiltIn, userId, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Preset &&
          other.id == this.id &&
          other.name == this.name &&
          other.category == this.category &&
          other.parameters == this.parameters &&
          other.isBuiltIn == this.isBuiltIn &&
          other.userId == this.userId &&
          other.updatedAt == this.updatedAt);
}

class PresetsCompanion extends UpdateCompanion<Preset> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> category;
  final Value<String> parameters;
  final Value<bool> isBuiltIn;
  final Value<String?> userId;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const PresetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.category = const Value.absent(),
    this.parameters = const Value.absent(),
    this.isBuiltIn = const Value.absent(),
    this.userId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PresetsCompanion.insert({
    required String id,
    required String name,
    required String category,
    required String parameters,
    this.isBuiltIn = const Value.absent(),
    this.userId = const Value.absent(),
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        category = Value(category),
        parameters = Value(parameters),
        updatedAt = Value(updatedAt);
  static Insertable<Preset> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? category,
    Expression<String>? parameters,
    Expression<bool>? isBuiltIn,
    Expression<String>? userId,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (parameters != null) 'parameters': parameters,
      if (isBuiltIn != null) 'is_built_in': isBuiltIn,
      if (userId != null) 'user_id': userId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PresetsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String>? category,
      Value<String>? parameters,
      Value<bool>? isBuiltIn,
      Value<String?>? userId,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return PresetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      parameters: parameters ?? this.parameters,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      userId: userId ?? this.userId,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (parameters.present) {
      map['parameters'] = Variable<String>(parameters.value);
    }
    if (isBuiltIn.present) {
      map['is_built_in'] = Variable<bool>(isBuiltIn.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PresetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('parameters: $parameters, ')
          ..write('isBuiltIn: $isBuiltIn, ')
          ..write('userId: $userId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  _$AppDatabase.connect(DatabaseConnection c) : super.connect(c);
  _$AppDatabaseManager get managers => _$AppDatabaseManager(this);
  late final $UserProfilesTable userProfiles = $UserProfilesTable(this);
  late final $ProjectsTable projects = $ProjectsTable(this);
  late final $VideoSourcesTable videoSources = $VideoSourcesTable(this);
  late final $TimeslotsTable timeslots = $TimeslotsTable(this);
  late final $TemplatesTable templates = $TemplatesTable(this);
  late final $FixesTable fixes = $FixesTable(this);
  late final $PresetsTable presets = $PresetsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        userProfiles,
        projects,
        videoSources,
        timeslots,
        templates,
        fixes,
        presets
      ];
}

typedef $$UserProfilesTableInsertCompanionBuilder = UserProfilesCompanion
    Function({
  required String id,
  required String displayName,
  Value<String?> avatarPath,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$UserProfilesTableUpdateCompanionBuilder = UserProfilesCompanion
    Function({
  Value<String> id,
  Value<String> displayName,
  Value<String?> avatarPath,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$UserProfilesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $UserProfilesTable,
    UserProfile,
    $$UserProfilesTableFilterComposer,
    $$UserProfilesTableOrderingComposer,
    $$UserProfilesTableProcessedTableManager,
    $$UserProfilesTableInsertCompanionBuilder,
    $$UserProfilesTableUpdateCompanionBuilder> {
  $$UserProfilesTableTableManager(_$AppDatabase db, $UserProfilesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$UserProfilesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$UserProfilesTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$UserProfilesTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<String?> avatarPath = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              UserProfilesCompanion(
            id: id,
            displayName: displayName,
            avatarPath: avatarPath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String displayName,
            Value<String?> avatarPath = const Value.absent(),
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              UserProfilesCompanion.insert(
            id: id,
            displayName: displayName,
            avatarPath: avatarPath,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$UserProfilesTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $UserProfilesTable,
    UserProfile,
    $$UserProfilesTableFilterComposer,
    $$UserProfilesTableOrderingComposer,
    $$UserProfilesTableProcessedTableManager,
    $$UserProfilesTableInsertCompanionBuilder,
    $$UserProfilesTableUpdateCompanionBuilder> {
  $$UserProfilesTableProcessedTableManager(super.$state);
}

class $$UserProfilesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $UserProfilesTable> {
  $$UserProfilesTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get displayName => $state.composableBuilder(
      column: $state.table.displayName,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get avatarPath => $state.composableBuilder(
      column: $state.table.avatarPath,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ComposableFilter projectsRefs(
      ComposableFilter Function($$ProjectsTableFilterComposer f) f) {
    final $$ProjectsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.userId,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableFilterComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter presetsRefs(
      ComposableFilter Function($$PresetsTableFilterComposer f) f) {
    final $$PresetsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.presets,
        getReferencedColumn: (t) => t.userId,
        builder: (joinBuilder, parentComposers) => $$PresetsTableFilterComposer(
            ComposerState(
                $state.db, $state.db.presets, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$UserProfilesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $UserProfilesTable> {
  $$UserProfilesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get displayName => $state.composableBuilder(
      column: $state.table.displayName,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get avatarPath => $state.composableBuilder(
      column: $state.table.avatarPath,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$ProjectsTableInsertCompanionBuilder = ProjectsCompanion Function({
  required String id,
  required String name,
  required String userId,
  required DateTime createdAt,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$ProjectsTableUpdateCompanionBuilder = ProjectsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> userId,
  Value<DateTime> createdAt,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$ProjectsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ProjectsTable,
    Project,
    $$ProjectsTableFilterComposer,
    $$ProjectsTableOrderingComposer,
    $$ProjectsTableProcessedTableManager,
    $$ProjectsTableInsertCompanionBuilder,
    $$ProjectsTableUpdateCompanionBuilder> {
  $$ProjectsTableTableManager(_$AppDatabase db, $ProjectsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$ProjectsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$ProjectsTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$ProjectsTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> userId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ProjectsCompanion(
            id: id,
            name: name,
            userId: userId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String name,
            required String userId,
            required DateTime createdAt,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              ProjectsCompanion.insert(
            id: id,
            name: name,
            userId: userId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$ProjectsTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $ProjectsTable,
    Project,
    $$ProjectsTableFilterComposer,
    $$ProjectsTableOrderingComposer,
    $$ProjectsTableProcessedTableManager,
    $$ProjectsTableInsertCompanionBuilder,
    $$ProjectsTableUpdateCompanionBuilder> {
  $$ProjectsTableProcessedTableManager(super.$state);
}

class $$ProjectsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$UserProfilesTableFilterComposer get userId {
    final $$UserProfilesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.userId,
        referencedTable: $state.db.userProfiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$UserProfilesTableFilterComposer(ComposerState($state.db,
                $state.db.userProfiles, joinBuilder, parentComposers)));
    return composer;
  }

  ComposableFilter videoSourcesRefs(
      ComposableFilter Function($$VideoSourcesTableFilterComposer f) f) {
    final $$VideoSourcesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.videoSources,
        getReferencedColumn: (t) => t.projectId,
        builder: (joinBuilder, parentComposers) =>
            $$VideoSourcesTableFilterComposer(ComposerState($state.db,
                $state.db.videoSources, joinBuilder, parentComposers)));
    return f(composer);
  }

  ComposableFilter timeslotsRefs(
      ComposableFilter Function($$TimeslotsTableFilterComposer f) f) {
    final $$TimeslotsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.timeslots,
        getReferencedColumn: (t) => t.projectId,
        builder: (joinBuilder, parentComposers) =>
            $$TimeslotsTableFilterComposer(ComposerState(
                $state.db, $state.db.timeslots, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$ProjectsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $ProjectsTable> {
  $$ProjectsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$UserProfilesTableOrderingComposer get userId {
    final $$UserProfilesTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.userId,
        referencedTable: $state.db.userProfiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$UserProfilesTableOrderingComposer(ComposerState($state.db,
                $state.db.userProfiles, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$VideoSourcesTableInsertCompanionBuilder = VideoSourcesCompanion
    Function({
  required String id,
  required String projectId,
  required String filePath,
  required int durationMs,
  required int width,
  required int height,
  required String codecName,
  required double fps,
  Value<String?> thumbnailPath,
  required DateTime createdAt,
  Value<int> rowid,
});
typedef $$VideoSourcesTableUpdateCompanionBuilder = VideoSourcesCompanion
    Function({
  Value<String> id,
  Value<String> projectId,
  Value<String> filePath,
  Value<int> durationMs,
  Value<int> width,
  Value<int> height,
  Value<String> codecName,
  Value<double> fps,
  Value<String?> thumbnailPath,
  Value<DateTime> createdAt,
  Value<int> rowid,
});

class $$VideoSourcesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $VideoSourcesTable,
    VideoSource,
    $$VideoSourcesTableFilterComposer,
    $$VideoSourcesTableOrderingComposer,
    $$VideoSourcesTableProcessedTableManager,
    $$VideoSourcesTableInsertCompanionBuilder,
    $$VideoSourcesTableUpdateCompanionBuilder> {
  $$VideoSourcesTableTableManager(_$AppDatabase db, $VideoSourcesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$VideoSourcesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$VideoSourcesTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$VideoSourcesTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> projectId = const Value.absent(),
            Value<String> filePath = const Value.absent(),
            Value<int> durationMs = const Value.absent(),
            Value<int> width = const Value.absent(),
            Value<int> height = const Value.absent(),
            Value<String> codecName = const Value.absent(),
            Value<double> fps = const Value.absent(),
            Value<String?> thumbnailPath = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              VideoSourcesCompanion(
            id: id,
            projectId: projectId,
            filePath: filePath,
            durationMs: durationMs,
            width: width,
            height: height,
            codecName: codecName,
            fps: fps,
            thumbnailPath: thumbnailPath,
            createdAt: createdAt,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String projectId,
            required String filePath,
            required int durationMs,
            required int width,
            required int height,
            required String codecName,
            required double fps,
            Value<String?> thumbnailPath = const Value.absent(),
            required DateTime createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              VideoSourcesCompanion.insert(
            id: id,
            projectId: projectId,
            filePath: filePath,
            durationMs: durationMs,
            width: width,
            height: height,
            codecName: codecName,
            fps: fps,
            thumbnailPath: thumbnailPath,
            createdAt: createdAt,
            rowid: rowid,
          ),
        ));
}

class $$VideoSourcesTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $VideoSourcesTable,
    VideoSource,
    $$VideoSourcesTableFilterComposer,
    $$VideoSourcesTableOrderingComposer,
    $$VideoSourcesTableProcessedTableManager,
    $$VideoSourcesTableInsertCompanionBuilder,
    $$VideoSourcesTableUpdateCompanionBuilder> {
  $$VideoSourcesTableProcessedTableManager(super.$state);
}

class $$VideoSourcesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $VideoSourcesTable> {
  $$VideoSourcesTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get filePath => $state.composableBuilder(
      column: $state.table.filePath,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get durationMs => $state.composableBuilder(
      column: $state.table.durationMs,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get width => $state.composableBuilder(
      column: $state.table.width,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get height => $state.composableBuilder(
      column: $state.table.height,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get codecName => $state.composableBuilder(
      column: $state.table.codecName,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<double> get fps => $state.composableBuilder(
      column: $state.table.fps,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get thumbnailPath => $state.composableBuilder(
      column: $state.table.thumbnailPath,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableFilterComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return composer;
  }

  ComposableFilter timeslotsRefs(
      ComposableFilter Function($$TimeslotsTableFilterComposer f) f) {
    final $$TimeslotsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $state.db.timeslots,
        getReferencedColumn: (t) => t.videoSourceId,
        builder: (joinBuilder, parentComposers) =>
            $$TimeslotsTableFilterComposer(ComposerState(
                $state.db, $state.db.timeslots, joinBuilder, parentComposers)));
    return f(composer);
  }
}

class $$VideoSourcesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $VideoSourcesTable> {
  $$VideoSourcesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get filePath => $state.composableBuilder(
      column: $state.table.filePath,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get durationMs => $state.composableBuilder(
      column: $state.table.durationMs,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get width => $state.composableBuilder(
      column: $state.table.width,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get height => $state.composableBuilder(
      column: $state.table.height,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get codecName => $state.composableBuilder(
      column: $state.table.codecName,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<double> get fps => $state.composableBuilder(
      column: $state.table.fps,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get thumbnailPath => $state.composableBuilder(
      column: $state.table.thumbnailPath,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableOrderingComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$TimeslotsTableInsertCompanionBuilder = TimeslotsCompanion Function({
  required String id,
  required String projectId,
  required String videoSourceId,
  required int inPointMs,
  required int outPointMs,
  Value<String> label,
  Value<int> colorIndex,
  Value<int> rating,
  required DateTime createdAt,
  Value<String> filename,
  Value<String> description,
  Value<int> elapse,
  Value<bool> remote,
  Value<int> rowid,
});
typedef $$TimeslotsTableUpdateCompanionBuilder = TimeslotsCompanion Function({
  Value<String> id,
  Value<String> projectId,
  Value<String> videoSourceId,
  Value<int> inPointMs,
  Value<int> outPointMs,
  Value<String> label,
  Value<int> colorIndex,
  Value<int> rating,
  Value<DateTime> createdAt,
  Value<String> filename,
  Value<String> description,
  Value<int> elapse,
  Value<bool> remote,
  Value<int> rowid,
});

class $$TimeslotsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TimeslotsTable,
    Timeslot,
    $$TimeslotsTableFilterComposer,
    $$TimeslotsTableOrderingComposer,
    $$TimeslotsTableProcessedTableManager,
    $$TimeslotsTableInsertCompanionBuilder,
    $$TimeslotsTableUpdateCompanionBuilder> {
  $$TimeslotsTableTableManager(_$AppDatabase db, $TimeslotsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$TimeslotsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$TimeslotsTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$TimeslotsTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> projectId = const Value.absent(),
            Value<String> videoSourceId = const Value.absent(),
            Value<int> inPointMs = const Value.absent(),
            Value<int> outPointMs = const Value.absent(),
            Value<String> label = const Value.absent(),
            Value<int> colorIndex = const Value.absent(),
            Value<int> rating = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String> filename = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<int> elapse = const Value.absent(),
            Value<bool> remote = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TimeslotsCompanion(
            id: id,
            projectId: projectId,
            videoSourceId: videoSourceId,
            inPointMs: inPointMs,
            outPointMs: outPointMs,
            label: label,
            colorIndex: colorIndex,
            rating: rating,
            createdAt: createdAt,
            filename: filename,
            description: description,
            elapse: elapse,
            remote: remote,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String projectId,
            required String videoSourceId,
            required int inPointMs,
            required int outPointMs,
            Value<String> label = const Value.absent(),
            Value<int> colorIndex = const Value.absent(),
            Value<int> rating = const Value.absent(),
            required DateTime createdAt,
            Value<String> filename = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<int> elapse = const Value.absent(),
            Value<bool> remote = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TimeslotsCompanion.insert(
            id: id,
            projectId: projectId,
            videoSourceId: videoSourceId,
            inPointMs: inPointMs,
            outPointMs: outPointMs,
            label: label,
            colorIndex: colorIndex,
            rating: rating,
            createdAt: createdAt,
            filename: filename,
            description: description,
            elapse: elapse,
            remote: remote,
            rowid: rowid,
          ),
        ));
}

class $$TimeslotsTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $TimeslotsTable,
    Timeslot,
    $$TimeslotsTableFilterComposer,
    $$TimeslotsTableOrderingComposer,
    $$TimeslotsTableProcessedTableManager,
    $$TimeslotsTableInsertCompanionBuilder,
    $$TimeslotsTableUpdateCompanionBuilder> {
  $$TimeslotsTableProcessedTableManager(super.$state);
}

class $$TimeslotsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $TimeslotsTable> {
  $$TimeslotsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get inPointMs => $state.composableBuilder(
      column: $state.table.inPointMs,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get outPointMs => $state.composableBuilder(
      column: $state.table.outPointMs,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get label => $state.composableBuilder(
      column: $state.table.label,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get colorIndex => $state.composableBuilder(
      column: $state.table.colorIndex,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get rating => $state.composableBuilder(
      column: $state.table.rating,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get filename => $state.composableBuilder(
      column: $state.table.filename,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<int> get elapse => $state.composableBuilder(
      column: $state.table.elapse,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get remote => $state.composableBuilder(
      column: $state.table.remote,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$ProjectsTableFilterComposer get projectId {
    final $$ProjectsTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableFilterComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return composer;
  }

  $$VideoSourcesTableFilterComposer get videoSourceId {
    final $$VideoSourcesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.videoSourceId,
        referencedTable: $state.db.videoSources,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$VideoSourcesTableFilterComposer(ComposerState($state.db,
                $state.db.videoSources, joinBuilder, parentComposers)));
    return composer;
  }
}

class $$TimeslotsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $TimeslotsTable> {
  $$TimeslotsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get inPointMs => $state.composableBuilder(
      column: $state.table.inPointMs,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get outPointMs => $state.composableBuilder(
      column: $state.table.outPointMs,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get label => $state.composableBuilder(
      column: $state.table.label,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get colorIndex => $state.composableBuilder(
      column: $state.table.colorIndex,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get rating => $state.composableBuilder(
      column: $state.table.rating,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get createdAt => $state.composableBuilder(
      column: $state.table.createdAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get filename => $state.composableBuilder(
      column: $state.table.filename,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<int> get elapse => $state.composableBuilder(
      column: $state.table.elapse,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get remote => $state.composableBuilder(
      column: $state.table.remote,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$ProjectsTableOrderingComposer get projectId {
    final $$ProjectsTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.projectId,
        referencedTable: $state.db.projects,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$ProjectsTableOrderingComposer(ComposerState(
                $state.db, $state.db.projects, joinBuilder, parentComposers)));
    return composer;
  }

  $$VideoSourcesTableOrderingComposer get videoSourceId {
    final $$VideoSourcesTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.videoSourceId,
        referencedTable: $state.db.videoSources,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$VideoSourcesTableOrderingComposer(ComposerState($state.db,
                $state.db.videoSources, joinBuilder, parentComposers)));
    return composer;
  }
}

typedef $$TemplatesTableInsertCompanionBuilder = TemplatesCompanion Function({
  required String id,
  required String name,
  Value<String> path,
  required String type,
  Value<int> rowid,
});
typedef $$TemplatesTableUpdateCompanionBuilder = TemplatesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> path,
  Value<String> type,
  Value<int> rowid,
});

class $$TemplatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $TemplatesTable,
    Template,
    $$TemplatesTableFilterComposer,
    $$TemplatesTableOrderingComposer,
    $$TemplatesTableProcessedTableManager,
    $$TemplatesTableInsertCompanionBuilder,
    $$TemplatesTableUpdateCompanionBuilder> {
  $$TemplatesTableTableManager(_$AppDatabase db, $TemplatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$TemplatesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$TemplatesTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) =>
              $$TemplatesTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> path = const Value.absent(),
            Value<String> type = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              TemplatesCompanion(
            id: id,
            name: name,
            path: path,
            type: type,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String name,
            Value<String> path = const Value.absent(),
            required String type,
            Value<int> rowid = const Value.absent(),
          }) =>
              TemplatesCompanion.insert(
            id: id,
            name: name,
            path: path,
            type: type,
            rowid: rowid,
          ),
        ));
}

class $$TemplatesTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $TemplatesTable,
    Template,
    $$TemplatesTableFilterComposer,
    $$TemplatesTableOrderingComposer,
    $$TemplatesTableProcessedTableManager,
    $$TemplatesTableInsertCompanionBuilder,
    $$TemplatesTableUpdateCompanionBuilder> {
  $$TemplatesTableProcessedTableManager(super.$state);
}

class $$TemplatesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $TemplatesTable> {
  $$TemplatesTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get path => $state.composableBuilder(
      column: $state.table.path,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$TemplatesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $TemplatesTable> {
  $$TemplatesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get path => $state.composableBuilder(
      column: $state.table.path,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get type => $state.composableBuilder(
      column: $state.table.type,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$FixesTableInsertCompanionBuilder = FixesCompanion Function({
  required String id,
  required String description,
  Value<String> filesChanged,
  required DateTime resolvedAt,
  Value<int> rowid,
});
typedef $$FixesTableUpdateCompanionBuilder = FixesCompanion Function({
  Value<String> id,
  Value<String> description,
  Value<String> filesChanged,
  Value<DateTime> resolvedAt,
  Value<int> rowid,
});

class $$FixesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FixesTable,
    Fixe,
    $$FixesTableFilterComposer,
    $$FixesTableOrderingComposer,
    $$FixesTableProcessedTableManager,
    $$FixesTableInsertCompanionBuilder,
    $$FixesTableUpdateCompanionBuilder> {
  $$FixesTableTableManager(_$AppDatabase db, $FixesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$FixesTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$FixesTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) => $$FixesTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> description = const Value.absent(),
            Value<String> filesChanged = const Value.absent(),
            Value<DateTime> resolvedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FixesCompanion(
            id: id,
            description: description,
            filesChanged: filesChanged,
            resolvedAt: resolvedAt,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String description,
            Value<String> filesChanged = const Value.absent(),
            required DateTime resolvedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              FixesCompanion.insert(
            id: id,
            description: description,
            filesChanged: filesChanged,
            resolvedAt: resolvedAt,
            rowid: rowid,
          ),
        ));
}

class $$FixesTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $FixesTable,
    Fixe,
    $$FixesTableFilterComposer,
    $$FixesTableOrderingComposer,
    $$FixesTableProcessedTableManager,
    $$FixesTableInsertCompanionBuilder,
    $$FixesTableUpdateCompanionBuilder> {
  $$FixesTableProcessedTableManager(super.$state);
}

class $$FixesTableFilterComposer
    extends FilterComposer<_$AppDatabase, $FixesTable> {
  $$FixesTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get filesChanged => $state.composableBuilder(
      column: $state.table.filesChanged,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get resolvedAt => $state.composableBuilder(
      column: $state.table.resolvedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));
}

class $$FixesTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $FixesTable> {
  $$FixesTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get description => $state.composableBuilder(
      column: $state.table.description,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get filesChanged => $state.composableBuilder(
      column: $state.table.filesChanged,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get resolvedAt => $state.composableBuilder(
      column: $state.table.resolvedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));
}

typedef $$PresetsTableInsertCompanionBuilder = PresetsCompanion Function({
  required String id,
  required String name,
  required String category,
  required String parameters,
  Value<bool> isBuiltIn,
  Value<String?> userId,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$PresetsTableUpdateCompanionBuilder = PresetsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> category,
  Value<String> parameters,
  Value<bool> isBuiltIn,
  Value<String?> userId,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$PresetsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $PresetsTable,
    Preset,
    $$PresetsTableFilterComposer,
    $$PresetsTableOrderingComposer,
    $$PresetsTableProcessedTableManager,
    $$PresetsTableInsertCompanionBuilder,
    $$PresetsTableUpdateCompanionBuilder> {
  $$PresetsTableTableManager(_$AppDatabase db, $PresetsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          filteringComposer:
              $$PresetsTableFilterComposer(ComposerState(db, table)),
          orderingComposer:
              $$PresetsTableOrderingComposer(ComposerState(db, table)),
          getChildManagerBuilder: (p) => $$PresetsTableProcessedTableManager(p),
          getUpdateCompanionBuilder: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String> category = const Value.absent(),
            Value<String> parameters = const Value.absent(),
            Value<bool> isBuiltIn = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PresetsCompanion(
            id: id,
            name: name,
            category: category,
            parameters: parameters,
            isBuiltIn: isBuiltIn,
            userId: userId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          getInsertCompanionBuilder: ({
            required String id,
            required String name,
            required String category,
            required String parameters,
            Value<bool> isBuiltIn = const Value.absent(),
            Value<String?> userId = const Value.absent(),
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              PresetsCompanion.insert(
            id: id,
            name: name,
            category: category,
            parameters: parameters,
            isBuiltIn: isBuiltIn,
            userId: userId,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
        ));
}

class $$PresetsTableProcessedTableManager extends ProcessedTableManager<
    _$AppDatabase,
    $PresetsTable,
    Preset,
    $$PresetsTableFilterComposer,
    $$PresetsTableOrderingComposer,
    $$PresetsTableProcessedTableManager,
    $$PresetsTableInsertCompanionBuilder,
    $$PresetsTableUpdateCompanionBuilder> {
  $$PresetsTableProcessedTableManager(super.$state);
}

class $$PresetsTableFilterComposer
    extends FilterComposer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableFilterComposer(super.$state);
  ColumnFilters<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get category => $state.composableBuilder(
      column: $state.table.category,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<String> get parameters => $state.composableBuilder(
      column: $state.table.parameters,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<bool> get isBuiltIn => $state.composableBuilder(
      column: $state.table.isBuiltIn,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  ColumnFilters<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnFilters(column, joinBuilders: joinBuilders));

  $$UserProfilesTableFilterComposer get userId {
    final $$UserProfilesTableFilterComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.userId,
        referencedTable: $state.db.userProfiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$UserProfilesTableFilterComposer(ComposerState($state.db,
                $state.db.userProfiles, joinBuilder, parentComposers)));
    return composer;
  }
}

class $$PresetsTableOrderingComposer
    extends OrderingComposer<_$AppDatabase, $PresetsTable> {
  $$PresetsTableOrderingComposer(super.$state);
  ColumnOrderings<String> get id => $state.composableBuilder(
      column: $state.table.id,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get name => $state.composableBuilder(
      column: $state.table.name,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get category => $state.composableBuilder(
      column: $state.table.category,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<String> get parameters => $state.composableBuilder(
      column: $state.table.parameters,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<bool> get isBuiltIn => $state.composableBuilder(
      column: $state.table.isBuiltIn,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  ColumnOrderings<DateTime> get updatedAt => $state.composableBuilder(
      column: $state.table.updatedAt,
      builder: (column, joinBuilders) =>
          ColumnOrderings(column, joinBuilders: joinBuilders));

  $$UserProfilesTableOrderingComposer get userId {
    final $$UserProfilesTableOrderingComposer composer = $state.composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.userId,
        referencedTable: $state.db.userProfiles,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder, parentComposers) =>
            $$UserProfilesTableOrderingComposer(ComposerState($state.db,
                $state.db.userProfiles, joinBuilder, parentComposers)));
    return composer;
  }
}

class _$AppDatabaseManager {
  final _$AppDatabase _db;
  _$AppDatabaseManager(this._db);
  $$UserProfilesTableTableManager get userProfiles =>
      $$UserProfilesTableTableManager(_db, _db.userProfiles);
  $$ProjectsTableTableManager get projects =>
      $$ProjectsTableTableManager(_db, _db.projects);
  $$VideoSourcesTableTableManager get videoSources =>
      $$VideoSourcesTableTableManager(_db, _db.videoSources);
  $$TimeslotsTableTableManager get timeslots =>
      $$TimeslotsTableTableManager(_db, _db.timeslots);
  $$TemplatesTableTableManager get templates =>
      $$TemplatesTableTableManager(_db, _db.templates);
  $$FixesTableTableManager get fixes =>
      $$FixesTableTableManager(_db, _db.fixes);
  $$PresetsTableTableManager get presets =>
      $$PresetsTableTableManager(_db, _db.presets);
}
