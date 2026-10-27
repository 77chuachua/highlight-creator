import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/project_file.dart';
import 'package:highlight_creator/domain/entities/project.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/presentation/shell/template_state.dart';
import 'package:highlight_creator/domain/repositories/project_repository.dart';
import 'package:highlight_creator/domain/repositories/timeslot_repository.dart';
import 'package:highlight_creator/services/error_logger.dart';

/// Represents a snapshot for undo/redo support.
class _RecordSnapshot {
  final List<Project> projects;
  final Map<String, List<Timeslot>> timeslots;
  _RecordSnapshot(this.projects, this.timeslots);
}

/// ViewModel for the Record System module.
///
/// Manages projects, video sources, timeslots, and undo/redo.
class RecordViewModel extends Notifier<RecordState> {
  final Uuid _uuid = const Uuid();
  final List<_RecordSnapshot> _undoStack = [];
  final List<_RecordSnapshot> _redoStack = [];
  static const int _maxUndo = 50;

  /// Autosave writes the project to a dated `.hlcproj` under the results dir,
  /// refreshed every [autoSaveIntervalProvider] once the first source is added.
  Timer? _autoSaveTimer;
  String? _autoSavePath;

  /// Path of today's autosave file, or null before the first source is added.
  String? get autoSavePath => _autoSavePath;

  ProjectRepository get _projectRepo => ref.read(projectRepositoryProvider);
  TimeslotRepository get _timeslotRepo => ref.read(timeslotRepositoryProvider);

  @override
  RecordState build() {
    ref.onDispose(_stopAutoSave);
    return const RecordState();
  }

  void _stopAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
    _autoSavePath = null;
  }

  /// Build the `.hlcproj` JSON payload for the current state (shared by the
  /// manual Save As and the autosave writer).
  Map<String, dynamic> buildProjectJson() {
    final project = state.selectedProject;
    final templateSelections = <String, String?>{};
    for (final entry in ref.read(selectedTemplatesProvider).entries) {
      templateSelections[entry.key.name] = entry.value;
    }
    return {
      'name': project?.name ?? 'New Project',
      // Round-trips the project date so loading does not depend on the name.
      'date': projectDateValue(project?.createdAt ?? DateTime.now()),
      'sources': (project?.sources ?? const <VideoSource>[]).map((s) => {
        'id': s.id,
        'filePath': s.filePath,
        'durationMs': s.durationMs,
        'width': s.width,
        'height': s.height,
        'codecName': s.codecName,
        'fps': s.fps,
      }).toList(),
      'templateSelections': templateSelections,
      'timeslots': state.timeslots.map((s) => {
        'id': s.id,
        'videoSourceId': s.videoSourceId,
        'inPointMs': s.inPointMs,
        'outPointMs': s.outPointMs,
        'label': s.label,
        'colorIndex': s.colorIndex,
        'rating': s.rating,
        'filename': s.filename,
        'description': s.description,
        'elapse': s.elapse,
        'remote': s.remote,
        'centerX': s.centerX,
        'centerY': s.centerY,
      }).toList(),
    };
  }

  /// Resolve today's autosave path and arm the periodic timer (idempotent).
  void _ensureAutoSaveTarget() {
    if (_autoSavePath != null) return;
    final interval = ref.read(autoSaveIntervalProvider);
    if (interval == null) return;
    // Named after the project's date, not today: reopening next week must
    // still point at the same file.
    final date = state.selectedProject?.createdAt ?? DateTime.now();
    final dir = Directory(AppPaths.resultsDir)..createSync(recursive: true);
    _autoSavePath = '${dir.path}${Platform.pathSeparator}'
        '${projectDateValue(date)}.hlcproj';
    _autoSaveTimer ??= Timer.periodic(interval, (_) => unawaited(autoSaveNow()));
  }

  /// Write the current project to the dated autosave file. No-op when autosave
  /// is disabled, has not started, or no project is selected.
  /// Clears the dirty flag on success.
  Future<void> autoSaveNow() async {
    final path = _autoSavePath;
    if (path == null || state.selectedProject == null) return;
    try {
      await File(path)
          .writeAsString(const JsonEncoder.withIndent('  ').convert(buildProjectJson()));
      if (state.isDirty) {
        state = state.copyWith(isDirty: false, loadedFromPath: path);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st, source: 'autosave');
    }
  }

  Future<void> _startAutoSave() async {
    if (ref.read(autoSaveIntervalProvider) == null) return;
    _ensureAutoSaveTarget();
    await autoSaveNow();
  }

  /// Load projects from the repository into state.
  Future<void> refreshProjects() => _loadProjects();

  Future<void> _loadProjects() async {
    final projects = await _projectRepo.listAll();
    // Preserve selectedProjectId across reloads — only clear if the
    // selected project no longer exists in the list.
    final keepId = state.selectedProjectId;
    final stillExists = keepId != null && projects.any((p) => p.id == keepId);
    state = state.copyWith(
      projects: projects,
      clearSelection: !stillExists,
    );
  }

  // ─── Projects ─────────────────────────────────────────

  /// Mark project as saved (clear dirty flag and record save path).
  void markSaved(String path) {
    state = state.copyWith(isDirty: false, loadedFromPath: path);
  }

  /// Mark project as loaded from file.
  void markLoaded(String path) {
    state = state.copyWith(isDirty: false, loadedFromPath: path);
  }

  /// Create a new project (clears dirty flag).
  /// Create a project.
  ///
  /// [date] is the day the project *belongs to* (the match date), stored in
  /// `createdAt`: the Top-5 period is derived from it, so loading a
  /// 2026-10-21 project in week 44 must not move its reels to week 44.
  Future<void> createProject(String name, {DateTime? date}) async {
    _stopAutoSave();
    final project = await _projectRepo.create(Project(
      id: '',
      name: name,
      userId: 'local',
      createdAt: date ?? DateTime.now(),
      updatedAt: DateTime.now(),
    ));
    await _loadProjects();
    state = state.copyWith(selectedProjectId: project.id, timeslots: const []);

    // Clear template selections for the new project.
    ref.read(selectedTemplatesProvider.notifier).clear();
  }

  Future<void> deleteProject(String id) async {
    final slots = await _timeslotRepo.listByProject(id);
    for (final s in slots) {
      await _timeslotRepo.delete(s.id);
    }
    await _projectRepo.delete(id);
    if (state.selectedProjectId == id) {
      state = state.copyWith(selectedProjectId: null, selectedTimeslotId: null);
    }
    await _loadProjects();
  }

  void selectProject(String id) {
    state = state.copyWith(selectedProjectId: id, selectedTimeslotId: null);
    _loadTimeslots(id);
  }

  /// Ensure a project exists, auto-creating a default one if no project is selected.
  /// Returns the selected project ID.
  Future<String> ensureProject() async {
    if (state.selectedProjectId != null) return state.selectedProjectId!;
    await createProject('New Project');
    return state.selectedProjectId!;
  }

  // ─── Timeslots ────────────────────────────────────────

  Future<void> _loadTimeslots(String projectId) async {
    final slots = await _timeslotRepo.listByProject(projectId);
    state = state.copyWith(timeslots: slots);
  }

  Future<void> addTimeslot({
    required String videoSourceId,
    required int inPointMs,
    required int outPointMs,
    String filename = '',
    String description = '',
    int elapse = 0,
    bool remote = false,
  }) async {
    final pid = state.selectedProjectId;
    if (pid == null) return;
    unawaited(_pushUndo());
    await _timeslotRepo.create(Timeslot(
      id: '',
      projectId: pid,
      videoSourceId: videoSourceId,
      inPointMs: inPointMs,
      outPointMs: outPointMs,
      filename: filename,
      description: description,
      elapse: elapse,
      remote: remote,
      createdAt: DateTime.now(),
    ));
    await _loadTimeslots(pid);
    state = state.copyWith(isDirty: true);
  }

  Future<void> updateTimeslot(Timeslot slot) async {
    unawaited(_pushUndo());
    await _timeslotRepo.update(slot);
    await _loadTimeslots(slot.projectId);
    state = state.copyWith(isDirty: true);
  }

  Future<void> deleteTimeslot(String id) async {
    final slot = await _timeslotRepo.getById(id);
    if (slot == null) return;
    unawaited(_pushUndo());
    await _timeslotRepo.delete(id);
    await _loadTimeslots(slot.projectId);
    if (state.selectedTimeslotId == id) {
      state = state.copyWith(selectedTimeslotId: null, isDirty: true);
    } else {
      state = state.copyWith(isDirty: true);
    }
  }

  void selectTimeslot(String? id) {
    state = state.copyWith(selectedTimeslotId: id);
  }

  /// Mark a timeslot covering the 10 seconds before the current position.
  ///
  /// Per issues.md the Mark button creates a window whose start is 10s before
  /// `positionMs` and whose elapse is 10s (clamped so the start never goes
  /// below 0, e.g. when marking within the first 10 seconds of a video).
  Future<void> mark({
    required String videoSourceId,
    required int positionMs,
    required String filename,
    required String description,
    required bool remote,
  }) async {
    if (state.selectedProjectId == null) return;
    const windowMs = 10000;
    final inPoint = positionMs - windowMs < 0 ? 0 : positionMs - windowMs;
    await addTimeslot(
      videoSourceId: videoSourceId,
      inPointMs: inPoint,
      outPointMs: positionMs,
      filename: filename,
      description: description,
      elapse: positionMs - inPoint,
      remote: remote,
    );
  }

  /// Close the current project, resetting to a fresh state.
  void closeProject() {
    _stopAutoSave();
    state = state.copyWith(clearSelection: true, clearDirty: true);
    ref.read(selectedTemplatesProvider.notifier).clear();
  }

  // ─── Video Sources ────────────────────────────────────

  Future<void> addVideoSource(String projectId, VideoSource source) async {
    final project = await _projectRepo.getById(projectId);
    if (project == null) return;
    // Ensure the source has a unique id.
    final src = source.id.isEmpty ? source.copyWith(id: _uuid.v4()) : source;
    final updatedSources = [...project.sources, src];
    await _projectRepo.update(project.copyWith(sources: updatedSources));
    await _loadProjects();
    state = state.copyWith(isDirty: true);
    // Adding a source starts (or refreshes) today's autosave file.
    await _startAutoSave();
  }

  Future<void> removeVideoSource(String projectId, String sourceId) async {
    final project = await _projectRepo.getById(projectId);
    if (project == null) return;
    final updatedSources = project.sources.where((s) => s.id != sourceId).toList();
    await _projectRepo.update(project.copyWith(sources: updatedSources));
    await _loadProjects();
    state = state.copyWith(isDirty: true);
  }

  /// Replace a single video source's metadata (e.g. after probing it). By
  /// default marks the project dirty; background enrichment passes it false.
  Future<void> updateVideoSource(String projectId, VideoSource source,
      {bool markDirty = true}) async {
    final project = await _projectRepo.getById(projectId);
    if (project == null) return;
    final updated = project.copyWith(sources: [
      for (final s in project.sources)
        if (s.id == source.id) source else s,
    ]);
    await _projectRepo.update(updated);
    await _loadProjects();
    if (markDirty) state = state.copyWith(isDirty: true);
  }

  // ─── Undo / Redo ──────────────────────────────────────

  Future<void> _pushUndo() async {
    final projects = await _projectRepo.listAll();
    final timeslots = <String, List<Timeslot>>{};
    for (final p in projects) {
      timeslots[p.id] = await _timeslotRepo.listByProject(p.id);
    }
    _undoStack.add(_RecordSnapshot(
      projects.map((p) => p.copyWith()).toList(),
      timeslots,
    ));
    if (_undoStack.length > _maxUndo) _undoStack.removeAt(0);
    _redoStack.clear();
    state = state.copyWith(canUndo: true, canRedo: false);
  }

  Future<void> undo() async {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_RecordSnapshot(
      (await _projectRepo.listAll()).map((p) => p.copyWith()).toList(),
      {},
    ));
    final snapshot = _undoStack.removeLast();
    // Restore projects
    final current = await _projectRepo.listAll();
    for (final p in current) {
      await _projectRepo.delete(p.id);
    }
    for (final p in snapshot.projects) {
      await _projectRepo.create(p);
    }
    // Restore timeslots
    for (final entry in snapshot.timeslots.entries) {
      for (final s in entry.value) {
        await _timeslotRepo.create(s);
      }
    }
    await _loadProjects();
    if (state.selectedProjectId != null) {
      await _loadTimeslots(state.selectedProjectId!);
    }
    state = state.copyWith(
      canUndo: _undoStack.isNotEmpty,
      canRedo: true,
    );
  }

  Future<void> redo() async {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_RecordSnapshot(
      (await _projectRepo.listAll()).map((p) => p.copyWith()).toList(),
      {},
    ));
    final snapshot = _redoStack.removeLast();
    final current = await _projectRepo.listAll();
    for (final p in current) {
      await _projectRepo.delete(p.id);
    }
    for (final p in snapshot.projects) {
      await _projectRepo.create(p);
    }
    await _loadProjects();
    state = state.copyWith(
      canUndo: true,
      canRedo: _redoStack.isNotEmpty,
    );
  }

  // ─── Export ───────────────────────────────────────────

  String exportTimeslotsJson() {
    return jsonEncode(state.timeslots.map((s) => {
      'id': s.id,
      'projectId': s.projectId,
      'videoSourceId': s.videoSourceId,
      'inPointMs': s.inPointMs,
      'outPointMs': s.outPointMs,
      'label': s.label,
      'colorIndex': s.colorIndex,
      'rating': s.rating,
      'filename': s.filename,
      'description': s.description,
      'elapse': s.elapse,
      'remote': s.remote,
      'centerX': s.centerX,
      'centerY': s.centerY,
    }).toList());
  }

  String exportTimeslotsCsv() {
    final buf = StringBuffer('id,projectId,videoSourceId,inPointMs,outPointMs,label,colorIndex,rating,filename,description,elapse,remote,centerX,centerY\n');
    for (final s in state.timeslots) {
      buf.writeln('${s.id},${s.projectId},${s.videoSourceId},${s.inPointMs},${s.outPointMs},${s.label},${s.colorIndex},${s.rating},${s.filename},${s.description},${s.elapse},${s.remote},${s.centerX ?? ''},${s.centerY ?? ''}');
    }
    return buf.toString();
  }

  /// Load a project from a JSON map (hlcproj format).
  Future<void> loadProjectFromJson(Map<String, dynamic> json, {String? filePath}) async {
    final name = json['name'] as String? ?? 'Imported Project';

    // Create the project (this will clear previous selection and create fresh).
    // The date comes from the file: its `date` key, else its name.
    await createProject(name, date: projectDateOf(json, filePath));
    final pid = state.selectedProjectId;
    if (pid == null) return;

    // Load video sources.
    final sourcesJson = json['sources'] as List<dynamic>? ?? [];
    for (final s in sourcesJson) {
      final sMap = s as Map<String, dynamic>;
      await addVideoSource(
        pid,
        VideoSource(
          id: sMap['id'] as String? ?? '',
          projectId: pid,
          filePath: sMap['filePath'] as String? ?? '',
          durationMs: sMap['durationMs'] as int? ?? 0,
          width: sMap['width'] as int? ?? 0,
          height: sMap['height'] as int? ?? 0,
          codecName: sMap['codecName'] as String? ?? '',
          fps: (sMap['fps'] as num?)?.toDouble() ?? 0,
          createdAt: DateTime.now(),
        ),
      );
    }

    // Load timeslots.
    final timeslotsJson = json['timeslots'] as List<dynamic>? ?? [];
    for (final t in timeslotsJson) {
      final tMap = t as Map<String, dynamic>;
      await _timeslotRepo.create(Timeslot(
        id: tMap['id'] as String? ?? '',
        projectId: pid,
        videoSourceId: tMap['videoSourceId'] as String? ?? '',
        inPointMs: tMap['inPointMs'] as int? ?? 0,
        outPointMs: tMap['outPointMs'] as int? ?? 0,
        label: tMap['label'] as String? ?? '',
        colorIndex: tMap['colorIndex'] as int? ?? 0,
        rating: tMap['rating'] as int? ?? 0,
        filename: tMap['filename'] as String? ?? '',
        description: tMap['description'] as String? ?? '',
        elapse: tMap['elapse'] as int? ?? 0,
        remote: tMap['remote'] as bool? ?? false,
        centerX: (tMap['centerX'] as num?)?.toDouble(),
        centerY: (tMap['centerY'] as num?)?.toDouble(),
        createdAt: DateTime.now(),
      ));
    }

    await _loadTimeslots(pid);
    if (filePath != null) markLoaded(filePath);
  }
}

/// Immutable state for the Record module.
class RecordState {
  final List<Project> projects;
  final List<Timeslot> timeslots;
  final String? selectedProjectId;
  final String? selectedTimeslotId;
  final bool canUndo;
  final bool canRedo;
  final bool isDirty;
  final String? loadedFromPath;

  const RecordState({
    this.projects = const [],
    this.timeslots = const [],
    this.selectedProjectId,
    this.selectedTimeslotId,
    this.canUndo = false,
    this.canRedo = false,
    this.isDirty = false,
    this.loadedFromPath,
  });

  Project? get selectedProject =>
      selectedProjectId != null
          ? projects.cast<Project?>().firstWhere(
                (p) => p?.id == selectedProjectId,
                orElse: () => null,
              )
          : null;

  Timeslot? get selectedTimeslot =>
      selectedTimeslotId != null
          ? timeslots.cast<Timeslot?>().firstWhere(
                (s) => s?.id == selectedTimeslotId,
                orElse: () => null,
              )
          : null;

  RecordState copyWith({
    List<Project>? projects,
    List<Timeslot>? timeslots,
    String? selectedProjectId,
    String? selectedTimeslotId,
    bool? canUndo,
    bool? canRedo,
    bool? isDirty,
    String? loadedFromPath,
    bool clearSelection = false,
    bool clearDirty = false,
  }) {
    return RecordState(
      projects: projects ?? this.projects,
      timeslots: clearSelection
          ? const []
          : (timeslots ?? this.timeslots),
      selectedProjectId:
          clearSelection ? null : (selectedProjectId ?? this.selectedProjectId),
      selectedTimeslotId:
          clearSelection ? null : (selectedTimeslotId ?? this.selectedTimeslotId),
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      isDirty: clearDirty ? false : (isDirty ?? this.isDirty),
      loadedFromPath: clearDirty ? null : (loadedFromPath ?? this.loadedFromPath),
    );
  }
}

/// Riverpod provider for the Record ViewModel.
final recordProvider = NotifierProvider<RecordViewModel, RecordState>(
  RecordViewModel.new,
);

/// Autosave cadence. Disabled (null) by default so widget tests never leave a
/// pending periodic timer or start real disk I/O in the fake-async zone;
/// `main()` turns on the real 30s cadence with a ProviderScope override.
final autoSaveIntervalProvider = Provider<Duration?>((ref) => null);