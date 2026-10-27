import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/presentation/shell/template_editor_dialog.dart';
import 'package:highlight_creator/presentation/shell/template_state.dart';
import 'package:highlight_creator/services/template_generator_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Pre-render preview dialog: shows startup / transition / ending template
/// video previews (looping, muted), output resolution picker, and
/// Confirm / Cancel buttons.
///
/// Returns `(width, height)` on confirm, or `null` on cancel.
class PreviewDialog extends ConsumerStatefulWidget {
  final int maxSourceHeight;
  final int initialWidth;
  final int initialHeight;
  final int timeslotCount;
  final int totalElapseMs;
  final VideoProcessingService? service;

  const PreviewDialog({
    super.key,
    required this.maxSourceHeight,
    this.initialWidth = 1280,
    this.initialHeight = 720,
    this.timeslotCount = 0,
    this.totalElapseMs = 0,
    this.service,
  });

  @override
  ConsumerState<PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends ConsumerState<PreviewDialog> {
  late int _selectedWidth;
  late int _selectedHeight;
  // Reassigned after the template editor closes to reload the previews, so it
  // must NOT be `final` (a second assignment threw LateInitializationError and
  // left the preview players disposed, i.e. playback dead after editing).
  late Future<List<_TemplateInfo>> _templatesFuture;
  late final Directory _tempDir;

  // One player per template slot (startup, transition, ending).
  final List<Player?> _players = [null, null, null];
  final List<VideoController?> _controllers = [null, null, null];
  final List<bool> _loading = [true, true, true];

  static const _presets = <({String label, int width, int height, int minSourceH})>[
    (label: '480P', width: 854, height: 480, minSourceH: 0),
    (label: '720P', width: 1280, height: 720, minSourceH: 0),
    (label: '1080P', width: 1920, height: 1080, minSourceH: 1080),
    (label: '4K', width: 3840, height: 2160, minSourceH: 2160),
  ];

  int get _selectedPresetIndex {
    for (var i = 0; i < _presets.length; i++) {
      if (_presets[i].width == _selectedWidth &&
          _presets[i].height == _selectedHeight) {
        return i;
      }
    }
    return 1; // default 720P
  }

  @override
  void initState() {
    super.initState();
    _selectedWidth = widget.initialWidth;
    _selectedHeight = widget.initialHeight;
    _tempDir = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'hl_preview_${DateTime.now().millisecondsSinceEpoch}',
    );
    _tempDir.createSync(recursive: true);
    _templatesFuture = _loadTemplates();
  }

  @override
  void dispose() {
    for (final p in _players) {
      p?.dispose();
    }
    try {
      _tempDir.deleteSync(recursive: true);
    } catch (_) {}
    super.dispose();
  }

  String _s(String zh, String en) =>
      ref.read(languageProvider) == '中文' ? zh : en;

  Future<void> _initPlayer(int index, String path, Template? tmpl) async {
    if (!File(path).existsSync()) return;
    final player = Player();
    final controller = VideoController(player);
    unawaited(player.setPlaylistMode(PlaylistMode.single));
    unawaited(player.setVolume(0));
    _players[index] = player;
    _controllers[index] = controller;

    // Render text overlay if the template has a title AND text is shown.
    // Mirrors the template config dialog, which hides text when the eye
    // toggle (persisted `showText`) is off.
    String playPath = path;
    final text = tmpl?.title ??
        TemplateEditorDialog.defaultStartupTitle(ref.read(languageProvider));
    if (tmpl != null && tmpl.showText && text.isNotEmpty) {
      final vps = widget.service;
      if (vps != null) {
        final out = '${_tempDir.path}${Platform.pathSeparator}'
            'preview_${index}_${text.hashCode}.mp4';
        final yExpr = VideoProcessingService.textYExpr(
          tmpl.textPosition,
          transition: tmpl.type == TemplateType.transition,
        );
        final fontHex = _fontColorHex(tmpl.fontColor);
        final escapedFont = _escapeFontPath(tmpl.fontPath);
        final res = await vps.overlayText(
          inputPath: path,
          outputPath: out,
          text: text,
          fontPath: escapedFont,
          fontSize: tmpl.fontSize ?? 42,
          fontColor: fontHex,
          yExpr: yExpr,
        );
        if (res.exitCode == 0 && File(out).existsSync()) {
          playPath = out;
        }
      }
    }

    await player.open(Media(playPath));
    if (mounted) {
      setState(() => _loading[index] = false);
    }
  }

  String _fontColorHex(String? color) {
    if (color == null || color.isEmpty) return '#F5C42D';
    return color.startsWith('#') ? color : '#$color';
  }

  String? _escapeFontPath(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return raw.replaceAll('\\', '/').replaceAll(':', r'\:');
  }

  TemplateCategory _typeToCategory(TemplateType type) => switch (type) {
        TemplateType.startup => TemplateCategory.startup,
        TemplateType.transition => TemplateCategory.transition,
        TemplateType.ending => TemplateCategory.ending,
        TemplateType.backgroundMusic => TemplateCategory.startup,
      };

  Future<void> _openTemplateEditor(TemplateType type) async {
    await showDialog(
      context: context,
      builder: (_) => TemplateEditorDialog(
        initialCategory: _typeToCategory(type),
      ),
    );
    // Reload after the editor closes so the preview shows the saved changes.
    _reloadPreviews();
  }

  /// Change which template a row renders, from inside the Make dialog.
  ///
  /// Picking a startup also adopts that design set's transition and ending; a
  /// later explicit pick of either is kept as-is.
  Future<void> _selectTemplate(TemplateType type, String id) async {
    final notifier = ref.read(selectedTemplatesProvider.notifier);
    if (type == TemplateType.startup) {
      await notifier.selectStartupWithSet(id);
    } else {
      notifier.select(type, id);
    }
    _reloadPreviews();
  }

  /// Drop the cached players and re-resolve every row from the repository.
  void _reloadPreviews() {
    if (!mounted) return;
    for (final p in _players) {
      unawaited(p?.dispose());
    }
    for (var i = 0; i < _players.length; i++) {
      _players[i] = null;
      _controllers[i] = null;
      _loading[i] = true;
    }
    setState(() {
      _templatesFuture = _loadTemplates();
    });
  }

  Future<Template?> _resolveTemplate(TemplateType type) async {
    final repo = ref.read(templateRepositoryProvider);
    final selected = ref.read(selectedTemplatesProvider);
    final selectedId = selected[type];
    Template? tmpl;
    if (selectedId != null) {
      tmpl = await repo.getById(selectedId);
    }
    if (tmpl == null) {
      final list = await repo.listByType(type);
      tmpl = list.isNotEmpty ? list.first : null;
    }
    return tmpl;
  }

  String? _resolvePath(Template? tmpl) {
    if (tmpl == null || tmpl.path.isEmpty) return null;
    if (File(tmpl.path).isAbsolute) return tmpl.path;
    var dir = Directory.current;
    while (true) {
      if (File('${dir.path}\\AGENTS.md').existsSync() ||
          Directory('${dir.path}\\app').existsSync()) {
        return '${dir.path}\\${tmpl.path}';
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
    return tmpl.path;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surfaceContainer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1400, maxHeight: 1100),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.visibility, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    l10n.previewDialogTitle,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        height: 400,
                        child: FutureBuilder<List<_TemplateInfo>>(
                          future: _templatesFuture,
                          builder: (context, snap) {
                            final templates = snap.data;
                            if (templates == null) {
                              return const Center(
                                  child: CircularProgressIndicator());
                            }
                            return _buildTemplatePreviews(templates, l10n);
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildResolutionPicker(l10n),
                      const SizedBox(height: 12),
                      _buildTimeslotSummary(l10n),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: const Key('preview_confirm_button'),
                    onPressed: () => Navigator.pop(
                        context, (_selectedWidth, _selectedHeight)),
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(l10n.previewConfirm),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<List<_TemplateInfo>> _loadTemplates() async {
    try {
      final startup = await _resolveTemplate(TemplateType.startup);
      final transition = await _resolveTemplate(TemplateType.transition);
      final ending = await _resolveTemplate(TemplateType.ending);
      final repo = ref.read(templateRepositoryProvider);
      final startupOptions = await repo.listByType(TemplateType.startup);
      final transitionOptions = await repo.listByType(TemplateType.transition);
      final endingOptions = await repo.listByType(TemplateType.ending);
      final list = [
        _TemplateInfo(
          type: TemplateType.startup,
          template: startup,
          path: _resolvePath(startup),
          title: startup?.title,
          options: startupOptions,
        ),
        _TemplateInfo(
          type: TemplateType.transition,
          template: transition,
          path: _resolvePath(transition),
          title: transition?.title,
          options: transitionOptions,
        ),
        _TemplateInfo(
          type: TemplateType.ending,
          template: ending,
          path: _resolvePath(ending),
          title: null,
          options: endingOptions,
        ),
      ];
      // Init players for each template that has a valid path.
      for (var i = 0; i < list.length; i++) {
        if (list[i].path != null) {
          unawaited(_initPlayer(i, list[i].path!, list[i].template));
        } else {
          _loading[i] = false;
        }
      }
      return list;
    } catch (_) {
      return [
        const _TemplateInfo(type: TemplateType.startup),
        const _TemplateInfo(type: TemplateType.transition),
        const _TemplateInfo(type: TemplateType.ending),
      ];
    }
  }

  Widget _buildTemplatePreviews(
      List<_TemplateInfo> templates, AppStrings l10n) {
    return Row(
      children: [
        for (var i = 0; i < templates.length; i++) ...[
          if (i > 0) ...[
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
            const SizedBox(width: 8),
          ],
          Expanded(child: _buildTemplateCard(i, templates[i], l10n)),
        ],
      ],
    );
  }

  Widget _buildTemplateCard(
      int index, _TemplateInfo info, AppStrings l10n) {
    final theme = Theme.of(context);
    final label = switch (info.type) {
      TemplateType.startup => l10n.previewStartupSection,
      TemplateType.transition => l10n.previewTransitionSection,
      TemplateType.ending => l10n.previewEndingSection,
      TemplateType.backgroundMusic => '',
    };

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  switch (info.type) {
                    TemplateType.startup => Icons.play_circle_outline,
                    TemplateType.transition => Icons.sync,
                    TemplateType.ending => Icons.stop_circle_outlined,
                    TemplateType.backgroundMusic => Icons.music_note,
                  },
                  size: 16,
                  color: Colors.white70,
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.edit, size: 14),
                  tooltip: _s('编辑模板', 'Edit template'),
                  onPressed: () => _openTemplateEditor(info.type),
                  visualDensity: VisualDensity.compact,
                  color: Colors.white54,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: double.infinity,
                  child: _buildVideoArea(index, info, l10n),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (info.options.length > 1)
              PopupMenuButton<String>(
                tooltip: _s('选择模板', 'Pick template'),
                onSelected: (id) => _selectTemplate(info.type, id),
                itemBuilder: (_) => [
                  for (final option in info.options)
                    PopupMenuItem(
                      value: option.id,
                      child: Row(
                        children: [
                          Icon(
                            option.id == info.template?.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(option.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        info.template?.name ?? '—',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.white70),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.arrow_drop_down,
                        size: 14, color: Colors.white54),
                  ],
                ),
              )
            else
              Text(
                info.template?.name ?? '—',
                style: const TextStyle(fontSize: 11, color: Colors.white70),
                overflow: TextOverflow.ellipsis,
              ),
            if (info.title != null && info.title!.isNotEmpty)
              Text(
                info.title!,
                style: const TextStyle(fontSize: 10, color: Colors.white54),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea(int index, _TemplateInfo info, AppStrings l10n) {
    if (info.path == null) {
      return Container(
        color: Colors.black38,
        child: Center(
          child: Text(
            l10n.previewNoEnding,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
      );
    }

    final controller = _controllers[index];
    if (controller != null && !_loading[index]) {
      return ColoredBox(
        color: Colors.black,
        child: Video(
          controller: controller,
          controls: NoVideoControls,
        ),
      );
    }

    return Container(
      color: Colors.black38,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildTimeslotSummary(AppStrings l10n) {
    return Row(
      children: [
        const Icon(Icons.list, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Text(
          '${widget.timeslotCount} ${l10n.previewTimeslotCount}',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
        const SizedBox(width: 16),
        const Icon(Icons.timelapse, size: 14, color: Colors.white54),
        const SizedBox(width: 6),
        Text(
          '${l10n.previewTotalElapse}${_formatMs(widget.totalElapseMs)}',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }

  /// Formats milliseconds as m:ss (or h:mm:ss when ≥ 1h).
  static String _formatMs(int ms) {
    final totalSecs = ms ~/ 1000;
    final h = totalSecs ~/ 3600;
    final m = (totalSecs % 3600) ~/ 60;
    final s = totalSecs % 60;
    final ss = s.toString().padLeft(2, '0');
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:$ss';
    }
    return '$m:$ss';
  }

  Widget _buildResolutionPicker(AppStrings l10n) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.outputResolution,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _presets.length; i++)
                  ChoiceChip(
                    // showCheckmark widens the selected chip and shuffles the row;
                    // the selected fill is signal enough.
                    showCheckmark: false,
                    key: Key('resolution_${_presets[i].label}'),
                    label: Text(_presets[i].label,
                        style: const TextStyle(fontSize: 12)),
                    selected: _selectedPresetIndex == i,
                    onSelected: _presets[i].minSourceH <= widget.maxSourceHeight
                        ? (selected) {
                            if (selected) {
                              setState(() {
                                _selectedWidth = _presets[i].width;
                                _selectedHeight = _presets[i].height;
                              });
                            }
                          }
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateInfo {
  final TemplateType type;
  final Template? template;
  final String? path;
  final String? title;

  /// Every template of this type, so the Make dialog can switch between them
  /// without leaving the preview.
  final List<Template> options;

  const _TemplateInfo({
    required this.type,
    this.template,
    this.path,
    this.title,
    this.options = const [],
  });
}
