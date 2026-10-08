import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';

/// Right sidebar panel listing source video files per the Windows UI design.
class SourceFileList extends ConsumerStatefulWidget {
  const SourceFileList({super.key});

  @override
  ConsumerState<SourceFileList> createState() => _SourceFileListState();
}

/// Pick video files and add them to the current project (shared by the
/// SourceFileList button and the Ctrl+A hotkey). Returns the first added
/// file path, or null if nothing was added.
Future<String?> pickAndAddSources(BuildContext context, WidgetRef ref) async {
  final l10n = ref.read(l10nProvider);
  final vm = ref.read(recordProvider.notifier);
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.video,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return null;

    final pid = await vm.ensureProject();
    String? firstAdded;
    for (final file in result.files) {
      if (file.path != null) {
        await vm.addVideoSource(
          pid,
          VideoSource(
            id: '', projectId: pid, filePath: file.path!,
            durationMs: 0, width: 0, height: 0,
            codecName: '', fps: 0, createdAt: DateTime.now(),
          ),
        );
        firstAdded ??= file.path;
      }
    }
    return firstAdded;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.failedToAddFiles}$e')),
      );
    }
    return null;
  }
}

class _SourceFileListState extends ConsumerState<SourceFileList> {
  StreamSubscription? _playbackEndSub;
  int _autoPlayIndex = -1;
  bool _autoAdvancing = false;
  bool _expanded = true;

  @override
  void dispose() {
    _playbackEndSub?.cancel();
    super.dispose();
  }

  Future<void> _addFiles(AppStrings l10n) async {
    final firstAdded = await pickAndAddSources(context, ref);
    // Start playing the first freshly added source (issues.md).
    if (firstAdded != null && mounted) {
      await _playSource(firstAdded);
    }
  }

  Future<void> _playSource(String filePath) async {
    await _playbackEndSub?.cancel();
    _autoAdvancing = false;

    final playerVm = ref.read(videoPlayerProvider.notifier);
    await playerVm.loadVideo(filePath);
    await playerVm.play();

    final sources = ref.read(recordProvider).selectedProject?.sources ?? [];
    _autoPlayIndex = sources.indexWhere((s) => s.filePath == filePath);
    _wireAutoPlay();
  }

  void _removeSource(String projectId, String sourceId) {
    ref.read(recordProvider.notifier).removeVideoSource(projectId, sourceId);
  }

  void _wireAutoPlay() {
    _playbackEndSub?.cancel();
    final player = ref.read(videoPlayerProvider.notifier).player;
    if (player == null) return;

    _playbackEndSub = player.stream.completed.listen((completed) {
      if (completed && !_autoAdvancing) {
        _advanceToNext();
      }
    });
  }

  Future<void> _advanceToNext() async {
    if (_autoAdvancing) return;
    _autoAdvancing = true;

    try {
      final project = ref.read(recordProvider).selectedProject;
      final sources = project?.sources ?? [];
      if (sources.isEmpty) {
        _autoAdvancing = false;
        return;
      }
      if (_autoPlayIndex >= sources.length - 1) {
        _autoAdvancing = false;
        return;
      }
      final nextIndex = _autoPlayIndex + 1;
      await _playSource(sources[nextIndex].filePath);
    } finally {
      _autoAdvancing = false;
    }
  }

  void wireAutoplayForCurrentVideo() {
    final state = ref.read(recordProvider);
    final playerState = ref.read(videoPlayerProvider);
    final project = state.selectedProject;
    final sources = project?.sources ?? [];
    final currentPath = playerState.videoPath;
    if (currentPath == null || sources.isEmpty) return;

    final index = sources.indexWhere((s) => s.filePath == currentPath);
    if (index >= 0) {
      _autoPlayIndex = index;
      _wireAutoPlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final state = ref.watch(recordProvider);
    final playerState = ref.watch(videoPlayerProvider);
    final theme = Theme.of(context);
    final project = state.selectedProject;
    final sources = project?.sources ?? [];
    final currentVideoPath = playerState.videoPath;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: theme.colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  child: AnimatedRotation(
                    turns: _expanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.arrow_right, size: 16, color: Colors.white54),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.video_library_outlined, size: 16, color: Colors.white54),
              const SizedBox(width: 6),
              Text(l10n.sourceFiles, style: theme.textTheme.titleSmall),
              const Spacer(),
              IconButton(
                key: const Key('source_add_button'),
                icon: const Icon(Icons.add, size: 16),
                tooltip: l10n.addVideoFiles,
                onPressed: () => _addFiles(l10n),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 28, minHeight: 28),
              ),
            ],
          ),
        ),
        if (_expanded)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: sources.isNotEmpty
                ? ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(4),
                    itemCount: sources.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final src = sources[i];
                      final isCurrent = src.filePath == currentVideoPath;
                      return ListTile(
                        dense: true,
                        selected: isCurrent,
                        selectedTileColor: theme.colorScheme.primary.withAlpha(30),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        leading: Icon(
                          isCurrent ? Icons.play_circle_filled : Icons.video_file,
                          size: 20,
                          color: isCurrent ? theme.colorScheme.primary : Colors.white54,
                        ),
                        title: Text(src.filePath.split('\\').last,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${formatHms(src.durationMs)} · ${src.width}×${src.height} · ${src.codecName}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white54)),
                        onTap: () => _playSource(src.filePath),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 14),
                          tooltip: l10n.removeFromList,
                          onPressed: () => _removeSource(project!.id, src.id),
                        ),
                      );
                    },
                  )
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: CustomPaint(
                      painter: _DashedBorderPainter(),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.video_library_outlined, size: 32, color: Colors.white54),
                            const SizedBox(height: 8),
                            Text(l10n.noVideoFiles, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                            const SizedBox(height: 4),
                            Text(l10n.clickToAdd, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed: () => _addFiles(l10n),
                              icon: const Icon(Icons.add, size: 16),
                              label: Text(l10n.addVideoFilesShort),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
      ],
    );
  }
}

/// Format a duration in ms as `h/m/s` (issues.md: the source list used to show
/// raw seconds e.g. "3600s"). Omits zero units:
///   90_000               → "1m 30s"
///   3_600_000 + 5_000     → "1h 5s"
///   12_000               → "12s"
String formatHms(int ms) {
  var totalSecs = (ms / 1000).round();
  final h = totalSecs ~/ 3600;
  totalSecs %= 3600;
  final m = totalSecs ~/ 60;
  final s = totalSecs % 60;
  final parts = <String>[];
  if (h > 0) parts.add('${h}h');
  if (m > 0) parts.add('${m}m');
  if (s > 0 || parts.isEmpty) parts.add('${s}s');
  return parts.join(' ');
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final path = Path();
    // Top
    for (double x = 0; x < size.width; x += dashWidth + dashSpace) {
      path.moveTo(x, 0);
      path.lineTo((x + dashWidth).clamp(0, size.width), 0);
    }
    // Bottom
    for (double x = 0; x < size.width; x += dashWidth + dashSpace) {
      path.moveTo(x, size.height);
      path.lineTo((x + dashWidth).clamp(0, size.width), size.height);
    }
    // Left
    for (double y = 0; y < size.height; y += dashWidth + dashSpace) {
      path.moveTo(0, y);
      path.lineTo(0, (y + dashWidth).clamp(0, size.height));
    }
    // Right
    for (double y = 0; y < size.height; y += dashWidth + dashSpace) {
      path.moveTo(size.width, y);
      path.lineTo(size.width, (y + dashWidth).clamp(0, size.height));
    }
    // Corner radii approximation
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}