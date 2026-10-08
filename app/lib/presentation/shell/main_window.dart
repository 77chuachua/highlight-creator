import 'dart:async';
import 'dart:convert';
import 'dart:io' show Directory, File, exit;
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart' as wm;
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/main.dart' show windowManager;
import 'package:highlight_creator/presentation/player/player_screen.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/presentation/shell/source_file_list.dart';
import 'package:highlight_creator/presentation/shell/template_panel.dart';
import 'package:highlight_creator/presentation/shell/control_panel.dart';
import 'package:highlight_creator/presentation/shell/timeslot_table.dart';
import 'package:highlight_creator/presentation/shell/status_bar.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/presentation/shell/guide_dialog.dart';
import 'package:highlight_creator/presentation/shell/settings_screen.dart';
import 'package:highlight_creator/presentation/shell/template_state.dart';
import 'package:highlight_creator/presentation/shell/timeline_track.dart';
import 'package:highlight_creator/presentation/shell/go_to_dialog.dart';
import 'package:highlight_creator/presentation/shell/template_editor_dialog.dart';
import 'package:highlight_creator/services/template_generator_service.dart';
import 'package:highlight_creator/data/settings_service.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';

/// Main single-window desktop layout per UIDesign/windows/layout.md.
class MainWindow extends ConsumerStatefulWidget {
  const MainWindow({super.key});

  @override
  ConsumerState<MainWindow> createState() => _MainWindowState();
}

class _MainWindowState extends ConsumerState<MainWindow> with wm.WindowListener {
  bool _showFileList = true;
  bool _showTimeslotTable = true;

  bool _defaultProjectCreated = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _createDefaultProject();
      _maybeShowGuide();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (_closing) return;
    final state = ref.read(recordProvider);
    if (!state.isDirty) {
      exit(0);
    }
    _showExitSaveDialog();
  }

  Future<void> _showExitSaveDialog() async {
    _closing = true;
    final l10n = ref.read(l10nProvider);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.unsavedChanges),
        content: Text(l10n.unsavedChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(l10n.discard),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (result == 'save') {
      final vm = ref.read(recordProvider.notifier);
      await _saveProject(l10n, vm);
    }
    if (result != 'cancel') {
      _closeApp();
    } else {
      _closing = false;
    }
  }

  void _closeApp() {
    // ponytail: window_manager.destroy() blocks the main thread on Windows.
    // Just exit — nothing to clean up that the OS won't handle.
    exit(0);
  }

  void _createDefaultProject() {
    if (_defaultProjectCreated) return;
    _defaultProjectCreated = true;
    ref.read(recordProvider.notifier).createProject('New Project');
  }

  /// Pop up the beginner guide on startup unless the user opted out.
  Future<void> _maybeShowGuide() async {
    final autoShow =
        await ref.read(settingsServiceProvider).guideAutoShow;
    if (!autoShow || !mounted) return;
    unawaited(showDialog<void>(
      context: context,
      builder: (_) => const GuideDialog(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: _onHotkey,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final state = ref.read(recordProvider);
        if (!state.isDirty) {
          Navigator.pop(context);
          return;
        }
        _showExitSaveDialog();
      },
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(context),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(
                    flex: 3,
                    child: PlayerScreen(),
                  ),
                  // Collapse/expand bar sits to the LEFT of the right panel
                  // (issues.md: it used to sit to the right of the panel).
                  GestureDetector(
                    key: const ValueKey('collapse_file_list_bar'),
                    onTap: () => setState(() => _showFileList = !_showFileList),
                    child: Container(
                      width: 20,
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          _showFileList ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_left,
                          size: 16,
                          color: Colors.white54,
                        ),
                      ),
                    ),
                  ),
                if (_showFileList)
                  const VerticalDivider(width: 1),
                if (_showFileList)
                  const SizedBox(
                    width: 320,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SourceFileList(),
                          SizedBox(height: 4),
                          TemplatePanel(
                            type: TemplateType.startup,
                            icon: Icons.movie_outlined,
                            iconColor: Color(0xFF42A5F5),
                          ),
                          SizedBox(height: 4),
                          TemplatePanel(
                            type: TemplateType.transition,
                            icon: Icons.auto_fix_high,
                            iconColor: Color(0xFF66BB6A),
                          ),
                          SizedBox(height: 4),
                          TemplatePanel(
                            type: TemplateType.ending,
                            icon: Icons.movie_filter_outlined,
                            iconColor: Color(0xFFEF5350),
                          ),
                          SizedBox(height: 4),
                          TemplatePanel(
                            type: TemplateType.backgroundMusic,
                            icon: Icons.music_note,
                            iconColor: Color(0xFFFFA726),
                          ),
                          SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const ControlPanel(),
          const _MainTrackerArea(),
          _buildTimeslotArea(),
          const StatusBar(),
        ],
        ),
      ),
    ),
  );
  }

  Widget _buildTimeslotArea() {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Toggle bar
          GestureDetector(
            onTap: () => setState(() => _showTimeslotTable = !_showTimeslotTable),
            child: Container(
              height: 20,
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Center(
                child: Icon(
                  _showTimeslotTable ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                  size: 14,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
          if (_showTimeslotTable)
            SizedBox(
              height: 200,
              child: TimeslotTable(onSlotTap: _playSlot),
            ),
        ],
      ),
    );
  }

  /// Play a clicked timeslot: load its source at the slot start, then play
  /// (issues.md: clicking a row in the timeslot list plays that slot).
  Future<void> _playSlot(Timeslot slot) async {
    final sources = ref.read(recordProvider).selectedProject?.sources ?? [];
    var seg = -1;
    if (slot.videoSourceId.isNotEmpty) {
      seg = sources.indexWhere((s) => s.id == slot.videoSourceId);
    }
    if (seg < 0 && slot.filename.isNotEmpty) {
      seg = sources.indexWhere(
          (s) => s.filePath.split(RegExp(r'[\\/]')).last == slot.filename);
    }
    if (seg < 0) return;
    final vm = ref.read(videoPlayerProvider.notifier);
    await vm.loadVideo(sources[seg].filePath,
        initialPosition: Duration(milliseconds: slot.inPointMs));
    await vm.play();
  }

  Widget _buildToolbar(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final recState = ref.watch(recordProvider);
    final recordVm = ref.read(recordProvider.notifier);

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.folder_open, size: 18),
            tooltip: l10n.projectMenu,
            offset: const Offset(0, 36),
            onSelected: (value) {
              switch (value) {
                case 'new':
                  _showNewProjectDialog(context, l10n, recordVm);
                  break;
                case 'save':
                  _saveProject(l10n, recordVm);
                  break;
                case 'load':
                  _loadProject(l10n, recordVm);
                  break;
                case 'close':
                  _closeProject(l10n, recordVm);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'new',
                child: Row(
                  children: [
                    const Icon(Icons.add, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.newProjectTitle),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'save',
                child: Row(
                  children: [
                    const Icon(Icons.save, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.saveProject),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'load',
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.loadProject),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'close',
                child: Row(
                  children: [
                    const Icon(Icons.close, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.closeProject),
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: Text(
              recState.selectedProject?.name ?? l10n.noProject,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings, size: 18),
            tooltip: l10n.settings,
            onPressed: () => _showSettings(context),
          ),
        ],
      ),
    );
  }

  void _showNewProjectDialog(BuildContext context, AppStrings l10n, RecordViewModel vm) async {
    if (!await _confirmUnsavedChanges()) return;
    if (!context.mounted) return;
    final ctrl = TextEditingController();
    unawaited(showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.newProjectTitle),
        content: TextField(
          controller: ctrl, autofocus: true,
          decoration: InputDecoration(hintText: l10n.projectNameHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                vm.createProject(ctrl.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: Text(l10n.create),
          ),
        ],
      ),
    ));
  }

  Future<void> _saveProject(AppStrings l10n, RecordViewModel recordVm) async {
    try {
      final state = ref.read(recordProvider);
      final project = state.selectedProject;
      if (project == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.noProjectToSave)),
          );
        }
        return;
      }

      final projectJson = recordVm.buildProjectJson();

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Project',
        fileName: '${project.name}.hlcproj',
        type: FileType.custom,
        allowedExtensions: ['hlcproj'],
      );

      if (result != null) {
        var path = result;
        if (!path.toLowerCase().endsWith('.hlcproj')) {
          path = '$path.hlcproj';
        }
        final file = File(path);
        await file.writeAsString(const JsonEncoder.withIndent('  ').convert(projectJson));
        recordVm.markSaved(path);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.projectSaved)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.saveFailed}$e')),
        );
      }
    }
  }

  Future<void> _loadProject(AppStrings l10n, RecordViewModel recordVm) async {
    try {
      if (!await _confirmUnsavedChanges()) return;

      final result = await FilePicker.platform.pickFiles(
        dialogTitle: 'Open Project',
        type: FileType.custom,
        allowedExtensions: ['hlcproj'],
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      final file = File(filePath);
      final jsonStr = await file.readAsString();
      final projectJson = jsonDecode(jsonStr) as Map<String, dynamic>;

      await recordVm.loadProjectFromJson(projectJson, filePath: filePath);

      // Restore template selections
      final templateSelections = projectJson['templateSelections'] as Map<String, dynamic>?;
      if (templateSelections != null) {
        final selected = ref.read(selectedTemplatesProvider.notifier);
        for (final entry in templateSelections.entries) {
          final type = TemplateType.values.firstWhere(
            (t) => t.name == entry.key,
            orElse: () => TemplateType.startup,
          );
          selected.select(type, entry.value as String?);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.projectLoaded)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.loadFailed}$e')),
        );
      }
    }
  }

  Future<void> _closeProject(AppStrings l10n, RecordViewModel recordVm) async {
    if (!await _confirmUnsavedChanges()) return;
    recordVm.closeProject();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.projectClosed)),
      );
    }
  }

  void _showSettings(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const Dialog(child: SizedBox(width: 500, child: SettingsScreen())),
    );
  }

  /// "I want to" menu moved to the ControlPanel (issues.md), so its actions
  /// now live next to it. Ctrl+G hotkey still opens the Go-to dialog.
  bool _isEditingText() {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    return ctx != null && ctx.widget is EditableText;
  }

  /// Global hotkeys (issues.md). Ctrl combos fire unless the user is typing
  /// in a text field; Space toggles play/pause.
  KeyEventResult _onHotkey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final l10n = ref.read(l10nProvider);
    final recVm = ref.read(recordProvider.notifier);
    final ctrl = HardwareKeyboard.instance.isControlPressed;
    if (!ctrl) {
      if (event.logicalKey == LogicalKeyboardKey.space && !_isEditingText()) {
        ref.read(videoPlayerProvider.notifier).togglePlayPause();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.keyM:
        ControlPanel.openMarkDialog(context, ref);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        ref.read(videoPlayerProvider.notifier)
            .seekRelative(const Duration(seconds: -5));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        ref.read(videoPlayerProvider.notifier)
            .seekRelative(const Duration(seconds: 5));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyG:
        openGoToDialog(context, ref);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyS:
        _saveProject(l10n, recVm);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyN:
        _showNewProjectDialog(context, l10n, recVm);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyO:
        _loadProject(l10n, recVm);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyQ:
        _closeProject(l10n, recVm);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyA:
        pickAndAddSources(context, ref);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyT:
        showDialog(
          context: context,
          builder: (_) => const TemplateEditorDialog(
            initialCategory: TemplateCategory.startup,
          ),
        );
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Check for unsaved changes and prompt user if needed. Returns true if safe to proceed.
  Future<bool> _confirmUnsavedChanges() async {
    final state = ref.read(recordProvider);
    if (!state.isDirty) return true;
    final l10n = ref.read(l10nProvider);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.unsavedChanges),
        content: Text(l10n.unsavedChangesMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(l10n.discard),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (result == 'save') {
      final vm = ref.read(recordProvider.notifier);
      await _saveProject(l10n, vm);
      return true;
    }
    return result == 'discard';
  }
}

/// Timeline track (moved from the auto-gen dialog per issues.md) driven by the
/// main single-video player. Shows ALL project sources on one global timeline
/// (ruler + preview thumbnails + draggable timeslot rects + live playhead),
/// exactly like the auto-gen dialog. Collapsible header, collapsed by default.
/// Click-to-seek and drag-resize seek through any source (loading it in the
/// main player when needed). Isolated as its own widget so live player
/// position updates only rebuild the track, not the whole window.
class _MainTrackerArea extends ConsumerStatefulWidget {
  const _MainTrackerArea();

  @override
  ConsumerState<_MainTrackerArea> createState() => _MainTrackerAreaState();
}

class _MainTrackerAreaState extends ConsumerState<_MainTrackerArea> {
  bool _expanded = false;

  // Probed metadata keyed by source path.
  final Map<String, int> _durationMsByPath = {};
  final Map<String, String?> _previewPathByPath = {};
  final Set<String> _probedPaths = {};
  String _lastSourceSig = '';

  String _sourceSig(List<VideoSource> sources) =>
      sources.map((s) => '${s.filePath}:${s.durationMs}').join('|');

  int _offsetMs(List<int> durations, int i) {
    var g = 0;
    for (var k = 0; k < i && k < durations.length; k++) {
      g += durations[k];
    }
    return g;
  }

  /// Probe metadata + extract preview frames for any source lacking them.
  /// Runs once per source; later source-list changes only probe new files.
  /// Also writes the probed metadata back to the stored VideoSource so the
  /// source list shows real duration/resolution/codec/fps (issues.md).
  Future<void> _probeSources(List<VideoSource> sources) async {
    try {
      final ffmpeg = await VideoProcessingService.findFfmpeg();
      final service = VideoProcessingService(ffmpegPath: ffmpeg);
      final tempDir =
          Directory.systemTemp.createTempSync('main_timeline_preview');
      final recVm = ref.read(recordProvider.notifier);
      final pid = ref.read(recordProvider).selectedProjectId;
      for (var i = 0; i < sources.length; i++) {
        final s = sources[i];
        if (_probedPaths.contains(s.filePath)) continue;
        final info = await VideoProcessingService.probeVideoInfo(s.filePath);
        final dur = info?.durationMs ??
            (s.durationMs > 0 ? s.durationMs : null);
        final outputPath = '${tempDir.path}\\preview_$i.png';
        final timestamp = math.min(1.0, (dur ?? 1000) / 1000.0);
        final result = await service.extractFrame(
          sourcePath: s.filePath,
          timestampSecs: timestamp,
          outputPath: outputPath,
          width: 160,
          height: 90,
        );
        final file = File(outputPath);
        final pv = result.exitCode == 0 &&
                file.existsSync() &&
                await file.length() > 0
            ? outputPath
            : null;
        if (!mounted) return;
        setState(() {
          if (dur != null) _durationMsByPath[s.filePath] = dur;
          _previewPathByPath[s.filePath] = pv;
          _probedPaths.add(s.filePath);
        });
        if (info != null &&
            pid != null &&
            (s.durationMs != info.durationMs ||
                s.width != info.width ||
                s.height != info.height ||
                s.codecName != info.codecName ||
                s.fps != info.fps)) {
          // Best-effort background write-back; never surfaces errors to the UI.
          unawaited(recVm
              .updateVideoSource(
                pid,
                s.copyWith(
                  durationMs: info.durationMs,
                  width: info.width,
                  height: info.height,
                  codecName: info.codecName,
                  fps: info.fps,
                ),
                markDirty: false,
              )
              .catchError((_) {}));
        }
      }
    } catch (_) {
      // Probe/preview failures (missing file, no ffmpeg) degrade gracefully:
      // the track still renders from source.durationMs with grey blocks.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final player = ref.watch(videoPlayerProvider);
    final recState = ref.watch(recordProvider);
    final project = recState.selectedProject;
    final sources = project?.sources ?? const <VideoSource>[];
    final vidPath = player.videoPath;

    // Refresh probed metadata when the source list changes (issues.md).
    final sig = _sourceSig(sources);
    if (sig != _lastSourceSig) {
      _lastSourceSig = sig;
      if (sources.isNotEmpty) _probeSources(sources);
    }

    final durations = <int>[
      for (final s in sources)
        _durationMsByPath[s.filePath] ?? (s.durationMs > 0 ? s.durationMs : 0),
    ];
    final previewPaths = <String?>[
      for (final s in sources) _previewPathByPath[s.filePath],
    ];

    final base = vidPath?.split(RegExp(r'[\\/]')).last;
    var currentIndex = -1;
    if (vidPath != null && base != null) {
      currentIndex = sources.indexWhere((s) =>
          s.filePath == vidPath ||
          s.filePath.split(RegExp(r'[\\/]')).last == base);
    }
    final totalMs = durations.fold(0, (a, b) => a + b);
    // Static fallback playhead x for tests/collapsed render; the live track
    // uses the VM's position notifier below (only the line repaints).
    final globalPosMs = currentIndex >= 0 && totalMs > 0
        ? (_offsetMs(durations, currentIndex) +
                ref.read(videoPlayerProvider.notifier).positionNotifier.value
                    .inMilliseconds)
            .clamp(0, totalMs)
        : 0;

    final playerVm = ref.read(videoPlayerProvider.notifier);
    final recVm = ref.read(recordProvider.notifier);

    Future<void> seekGlobal(int ms) async {
      if (totalMs <= 0) return;
      final t = globalToLocal(durations, ms);
      if (t.index == currentIndex && vidPath != null) {
        await playerVm.seek(Duration(milliseconds: t.localMs));
      } else if (t.index < sources.length) {
        // Reopen the target source with mpv's `start` set so it does NOT land
        // at the head of the video (regression fix, same as auto-gen dialog).
        await playerVm.loadVideo(
          sources[t.index].filePath,
          initialPosition: Duration(milliseconds: t.localMs),
        );
      }
    }

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Collapsible header — always visible, starts collapsed.
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.arrow_right,
                        size: 16, color: Colors.white54),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.timeline, size: 14, color: Colors.white54),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      l10n.timeline,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      base ?? '${sources.length} source(s)',
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white38),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded && totalMs > 0)
            TimelineTrack(
              sources: sources,
              durationsMs: durations,
              previewPaths: previewPaths,
              globalPositionMs: globalPosMs,
              livePosition:
                  ref.read(videoPlayerProvider.notifier).positionNotifier,
              positionSegment: currentIndex,
              segmentOf: (s) {
                if (s.videoSourceId.isNotEmpty) {
                  final i =
                      sources.indexWhere((x) => x.id == s.videoSourceId);
                  if (i >= 0) return i;
                }
                if (s.filename.isNotEmpty) {
                  final i = sources.indexWhere((x) =>
                      x.filePath.split(RegExp(r'[\\/]')).last == s.filename);
                  if (i >= 0) return i;
                }
                return -1;
              },
              onTrackTap: (ms) => seekGlobal(ms),
              onCommitDrag: (orig, inMs, outMs, seekMs) {
                recVm.updateTimeslot(orig.copyWith(
                  inPointMs: inMs,
                  outPointMs: outMs,
                  elapse: outMs - inMs,
                ));
                seekGlobal(seekMs);
              },
            ),
        ],
      ),
    );
  }
}