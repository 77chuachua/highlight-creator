import 'dart:async';
import 'dart:io' show Directory, File, Process;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/presentation/shell/go_to_dialog.dart';
import 'package:highlight_creator/presentation/shell/preview_dialog.dart';
import 'package:highlight_creator/presentation/shell/zoom_in_point_dialog.dart';
import 'package:highlight_creator/presentation/shell/template_state.dart';

/// Transport controls, mark, speed, make, undo/redo — per Windows UI design.
class ControlPanel extends ConsumerWidget {
  const ControlPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final playerState = ref.watch(videoPlayerProvider);
    final playerVm = ref.read(videoPlayerProvider.notifier);
    final recState = ref.watch(recordProvider);
    final theme = Theme.of(context);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outline.withAlpha(80)),
          bottom: BorderSide(color: theme.colorScheme.outline.withAlpha(80)),
        ),
      ),
      // Scrollable so the button row survives narrow windows / widget tests.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
          _IconBtn(Icons.replay_5, l10n.seekBack,
              () => playerVm.seekRelative(const Duration(seconds: -5))),
          const SizedBox(width: 2),
          _IconBtn(
            playerState.isPlaying ? Icons.pause : Icons.play_arrow,
            l10n.playPause,
            () => playerVm.togglePlayPause(),
            size: 28,
          ),
          const SizedBox(width: 2),
          _IconBtn(Icons.forward_5, l10n.seekForward,
              () => playerVm.seekRelative(const Duration(seconds: 5))),
          const SizedBox(width: 2),
          // Stop button hidden per user request.
          const VerticalDivider(width: 16),

          Tooltip(
            message: l10n.markTooltip,
            child: FilledButton.icon(
              key: const Key('mark_button'),
              onPressed: playerState.hasVideo
                  ? () => openMarkDialog(context, ref)
                  : null,
              icon: const Icon(Icons.outlined_flag, size: 16),
              label: Text(l10n.mark),
              style: FilledButton.styleFrom(
                minimumSize: const Size(110, 34),
                textStyle: const TextStyle(fontSize: 12),
                backgroundColor: Colors.amber.shade700,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.amber.shade700.withAlpha(60),
              ),
            ),
          ),
          const VerticalDivider(width: 16),

          SizedBox(
            width: 75,
            child: DropdownButtonFormField<double>(
              initialValue: playerState.playbackSpeed,
              isDense: true,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.speed,
                labelStyle: const TextStyle(fontSize: 10),
                floatingLabelBehavior: FloatingLabelBehavior.always,
                contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                border: const OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 0.5, child: Text('0.5x', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 1.0, child: Text('1.0x', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 1.5, child: Text('1.5x', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 2.0, child: Text('2.0x', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: 4.0, child: Text('4.0x', style: TextStyle(fontSize: 11))),
              ],
              onChanged: (v) {
                if (v != null) playerVm.setSpeed(v);
              },
            ),
          ),

          const VerticalDivider(width: 16),

          // "I want to" menu relocated here from the toolbar (issues.md:
          // Make + Result Folder buttons are gone; the menu covers both).
          PopupMenuButton<String>(
            key: const Key('want_menu'),
            tooltip: l10n.wantToMenu,
            position: PopupMenuPosition.over,
            offset: const Offset(0, -8),
            onSelected: (value) {
              switch (value) {
                case 'make':
                  openMakeFlow(context, ref);
                  break;
                case 'result':
                  openResultFolder();
                  break;
                case 'goto':
                  openGoToDialog(context, ref);
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'make',
                enabled: recState.timeslots.isNotEmpty,
                child: Row(
                  children: [
                    const Icon(Icons.auto_fix_high, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.wantMake),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'result',
                child: Row(
                  children: [
                    const Icon(Icons.folder_open, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.resultFolder),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'goto',
                child: Row(
                  children: [
                    const Icon(Icons.gps_fixed, size: 16),
                    const SizedBox(width: 8),
                    Text(l10n.wantGoTo),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.outline.withAlpha(80),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lightbulb_outline,
                      size: 15, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(l10n.wantToMenu,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const Icon(Icons.arrow_drop_down, size: 16),
                ],
              ),
            ),
          ),
          // Auto Gen button hidden per issues.md
          // const SizedBox(width: 2),
          // FilledButton.icon(
          //   key: const Key('auto_gen_button'),
          //   onPressed: (recState.selectedProject?.sources ?? []).isNotEmpty
          //       ? () => _onAutoGenPressed(context, ref, l10n, recVm)
          //       : null,
          //   icon: const Icon(Icons.auto_awesome, size: 16),
          //   label: Text(l10n.autoGen),
          //   style: FilledButton.styleFrom(
          //     minimumSize: const Size(100, 34),
          //     textStyle: const TextStyle(fontSize: 12, fontFamily: 'Roboto'),
          //     backgroundColor: Colors.purple.shade700,
          //     foregroundColor: Colors.white,
          //     disabledBackgroundColor: Colors.purple.shade700.withAlpha(60),
          //   ),
          // ),
          // Tooltip(
          //   message: l10n.autoGenTooltip,
          //   child: IconButton(
          //     icon: const Icon(Icons.info_outline, size: 16),
          //     onPressed: () {},
          //     visualDensity: VisualDensity.compact,
          //     color: Colors.white54,
          //   ),
          // ),
          ],
        ),
      ),
    );
  }

  /// Open the rendered-results folder in Explorer (also reachable from the
  /// "I want to" toolbar menu).
  static void openResultFolder() {
    try {
      Directory(AppPaths.resultsDir).createSync(recursive: true);
      Process.run('explorer', [AppPaths.resultsDir], runInShell: true);
    } catch (_) {}
  }

  /// Full Make flow: zoom-in dialog → preview/resolution dialog → render.
  /// Also reachable from the "I want to" toolbar menu and the Ctrl hotkeys.
  static Future<void> openMakeFlow(BuildContext context, WidgetRef ref) async {
    final l10n = ref.read(l10nProvider);
    final recVm = ref.read(recordProvider.notifier);
    final recState = ref.read(recordProvider);
    final project = recState.selectedProject;
    final sources = project?.sources ?? [];
    var timeslots = recState.timeslots;

    // Scan source file resolutions to determine max available.
    int maxSourceHeight = 2160; // default: allow all if we can't probe
    if (sources.isNotEmpty) {
      maxSourceHeight = 0;
      for (final s in sources) {
        final res = await VideoProcessingService.probeResolution(s.filePath);
        if (res != null) {
          if (res.$2 > maxSourceHeight) maxSourceHeight = res.$2;
        }
      }
      if (maxSourceHeight == 0) maxSourceHeight = 2160;
    }

    if (!context.mounted) return;

    // Resolve template paths for zoom-in dialog's temp dir.
    final outputDir = '${AppPaths.resultsDir}\\';
    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    final service = VideoProcessingService(ffmpegPath: ffmpegPath);
    if (!context.mounted) return;

    final sourceByPath = <String, String>{};
    for (final s in sources) {
      sourceByPath[s.filePath.split('\\').last] = s.filePath;
      sourceByPath[s.filePath.split('/').last] = s.filePath;
    }

    // Step 1: Zoom-in point dialog for remote timeslots (before preview).
    final remoteTimeslots = timeslots.where((t) => t.remote).toList();
    if (remoteTimeslots.isNotEmpty) {
      final marks = await showDialog<Map<String, Offset>>(
        context: context,
        builder: (ctx) => ZoomInPointDialog(
          remoteTimeslots: remoteTimeslots,
          sourcePaths: sourceByPath,
          tempDir: outputDir,
          service: service,
          l10n: l10n,
        ),
      );

      if (marks != null && marks.isNotEmpty) {
        timeslots = timeslots.map((t) {
          final m = marks[t.id];
          if (m != null) {
            return t.copyWith(centerX: m.dx, centerY: m.dy);
          }
          return t;
        }).toList();
      }
    }

    if (!context.mounted) return;

    // Step 2: Preview dialog with template previews + resolution selection.
    final totalElapseMs =
        timeslots.fold(0, (int sum, t) => sum + t.elapse);
    final resolution = await showDialog<(int, int)>(
      context: context,
      builder: (ctx) => PreviewDialog(
        maxSourceHeight: maxSourceHeight,
        timeslotCount: timeslots.length,
        totalElapseMs: totalElapseMs,
        service: service,
      ),
    );
    if (resolution == null) return; // user cancelled

    if (!context.mounted) return;

    // Step 3: Render with chosen resolution and updated timeslots.
    await _onMake(context, ref, l10n, recVm,
        width: resolution.$1,
        height: resolution.$2,
        timeslotsOverride: timeslots);
  }

  static Future<void> _onMake(
    BuildContext context,
    WidgetRef ref,
    AppStrings l10n,
    RecordViewModel recVm, {
    int width = 1280,
    int height = 720,
    List<Timeslot>? timeslotsOverride,
  }) async {
    final state = ref.read(recordProvider);
    final timeslots = timeslotsOverride ?? state.timeslots;
    final project = state.selectedProject;
    if (timeslots.isEmpty) return;

    final sources = project?.sources ?? [];
    final sourceByPath = <String, String>{};
    for (final s in sources) {
      sourceByPath[s.filePath.split('\\').last] = s.filePath;
      sourceByPath[s.filePath.split('/').last] = s.filePath;
    }

    String resolveProjectRoot() {
      var dir = Directory.current;
      while (true) {
        if (File('${dir.path}\\AGENTS.md').existsSync() ||
            Directory('${dir.path}\\app').existsSync()) {
          return dir.path;
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
      return Directory.current.path;
    }

    final projectRoot = resolveProjectRoot();
    final outputDir = '${AppPaths.resultsDir}\\';

    final templateRepo = ref.read(templateRepositoryProvider);
    final selected = ref.read(selectedTemplatesProvider);

    Future<Template?> resolveTemplate(TemplateType type) async {
      final selectedId = selected[type];
      Template? tmpl;
      if (selectedId != null) {
        tmpl = await templateRepo.getById(selectedId);
      }
      if (tmpl == null) {
        final list = await templateRepo.listByType(type);
        tmpl = list.isNotEmpty ? list.first : null;
      }
      return tmpl;
    }

    final startupTemplate = await resolveTemplate(TemplateType.startup);
    final startupPath = startupTemplate != null && startupTemplate.path.isNotEmpty
        ? (File(startupTemplate.path).isAbsolute
            ? startupTemplate.path
            : '$projectRoot\\${startupTemplate.path}')
        : null;

    final transitionTemplate = await resolveTemplate(TemplateType.transition);
    final transitionTemplatePath =
        transitionTemplate != null && transitionTemplate.path.isNotEmpty
            ? (File(transitionTemplate.path).isAbsolute
                ? transitionTemplate.path
                : '$projectRoot\\${transitionTemplate.path}')
            : null;

    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    final service = VideoProcessingService(ffmpegPath: ffmpegPath);

    if (!context.mounted) return;

    final endingTemplate = await resolveTemplate(TemplateType.ending);
    final endingPath = endingTemplate != null &&
            endingTemplate.path.isNotEmpty
        ? (File(endingTemplate.path).isAbsolute
            ? endingTemplate.path
            : '$projectRoot\\${endingTemplate.path}')
        : null;
    final bgMusicTemplate = await resolveTemplate(TemplateType.backgroundMusic);
    final bgMusicPath = bgMusicTemplate != null &&
            bgMusicTemplate.path.isNotEmpty
        ? (File(bgMusicTemplate.path).isAbsolute
            ? bgMusicTemplate.path
            : '$projectRoot\\${bgMusicTemplate.path}')
        : null;

    // Double-check all resolved template files exist before starting render.
    final missingTemplates = <String>[];
    String typeLabel(TemplateType t) {
      switch (t) {
        case TemplateType.startup: return l10n.startupTemplate;
        case TemplateType.transition: return l10n.transitionTemplate;
        case TemplateType.ending: return l10n.endingTemplate;
        case TemplateType.backgroundMusic: return l10n.backgroundMusic;
      }
    }
    void check(String? path, TemplateType type) {
      if (path == null) {
        missingTemplates.add('${typeLabel(type)}: ${l10n.noTemplates}');
      } else if (!File(path).existsSync()) {
        missingTemplates.add('${typeLabel(type)} — $path');
      }
    }
    check(startupPath, TemplateType.startup);
    check(transitionTemplatePath, TemplateType.transition);
    check(endingPath, TemplateType.ending);
    check(bgMusicPath, TemplateType.backgroundMusic);
    if (missingTemplates.isNotEmpty) {
      if (!context.mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: Text(l10n.missingTemplateFiles),
          content: Text('${l10n.templateFileNotFound}\n${missingTemplates.join('\n')}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.ok),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      return;
    }

    if (!context.mounted) return;

    bool dialogClosed = false;
    var progress = 0.0;
    void Function(VoidCallback)? refreshDialog;

    unawaited(showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          refreshDialog = setState;
          return AlertDialog(
            title: Text(l10n.renderDialogTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 16),
                SizedBox(
                  width: 90,
                  height: 90,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(value: progress),
                      ),
                      Text(
                        '${(progress * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(l10n.renderDialogMessage),
              ],
            ),
          );
        },
      ),
    ).then((_) {
      dialogClosed = true;
    }));

    try {
      final finalPath = await service.makeAll(
        timeslots: timeslots,
        startupVideoPath: startupPath ?? '',
        outputDir: outputDir,
        sourcePaths: sourceByPath,
        startupTemplate: startupTemplate,
        transitionTemplate: transitionTemplate,
        transitionTemplatePath: transitionTemplatePath,
        endingVideoPath: endingPath != null && File(endingPath).existsSync() ? endingPath : null,
        bgMusicPath: bgMusicPath != null && File(bgMusicPath).existsSync() ? bgMusicPath : null,
        width: width,
        height: height,
        onProgress: (p) {
          progress = p;
          refreshDialog?.call(() {});
        },
      );

      if (!context.mounted || dialogClosed) return;

      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.doneOutput}$finalPath'),
          backgroundColor: Colors.green.shade700,
          duration: const Duration(seconds: 4),
        ),
      );

      if (context.mounted) {
        unawaited(ref.read(videoPlayerProvider.notifier).loadVideo(finalPath));
      }
    } catch (e) {
      if (!context.mounted || dialogClosed) return;

      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${l10n.makeFailed}$e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  /// Mark dialog for the current playhead position. Also reachable from the
  /// Ctrl+M hotkey and the "I want to" menu (via a shared action).
  static void openMarkDialog(BuildContext context, WidgetRef ref) {
    final l10n = ref.read(l10nProvider);
    final playerVm = ref.read(videoPlayerProvider.notifier);
    final recVm = ref.read(recordProvider.notifier);
    final player = playerVm.player;
    final positionMs = player?.state.position.inMilliseconds ?? 0;
    final videoPath = ref.read(videoPlayerProvider).videoPath ?? '';
    final filename = videoPath.split('\\').last;

    playerVm.pause();

    final descCtrl = TextEditingController();
    bool remote = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.markTimeslot),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: l10n.descriptionHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: remote,
                    onChanged: (v) {
                      setDialogState(() => remote = v ?? false);
                    },
                  ),
                  Text(l10n.remote),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () async {
                await recVm.ensureProject();

                final project = ref.read(recordProvider).selectedProject;
                final sources = project?.sources ?? [];
                final vsId = sources
                    .where((s) => s.filePath == videoPath)
                    .map((s) => s.id)
                    .firstOrNull ?? '';

                try {
                  await recVm.mark(
                    videoSourceId: vsId,
                    positionMs: positionMs,
                    filename: filename,
                    description: descCtrl.text.trim(),
                    remote: remote,
                  );
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.timeslotMarked)),
                    );
                    unawaited(playerVm.play());
                  }
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('${l10n.failedToMark}$e')),
                    );
                  }
                }
              },
              child: Text(l10n.ok),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  const _IconBtn(this.icon, this.tooltip, this.onPressed, {this.size = 22});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: size),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      color: onPressed != null ? Colors.white70 : Colors.white24,
      splashRadius: 18,
    );
  }
}