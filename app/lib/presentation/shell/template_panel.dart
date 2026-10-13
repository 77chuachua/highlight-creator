import 'dart:async';
import 'dart:io' show Directory, File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/di/injection.dart';
import 'package:highlight_creator/domain/entities/template.dart';
import 'package:highlight_creator/presentation/shell/collapsible_panel.dart';
import 'package:highlight_creator/presentation/shell/template_editor_dialog.dart';
import 'package:highlight_creator/presentation/shell/template_state.dart';
import 'package:highlight_creator/services/template_generator_service.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class TemplatePanel extends ConsumerStatefulWidget {
  final TemplateType type;
  final IconData icon;
  final Color? iconColor;

  const TemplatePanel({
    super.key,
    required this.type,
    required this.icon,
    this.iconColor,
  });

  @override
  ConsumerState<TemplatePanel> createState() => _TemplatePanelState();
}

class _TemplatePanelState extends ConsumerState<TemplatePanel> {
  Future<List<Template>>? _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = ref.read(templateRepositoryProvider).listByType(widget.type);
  }

  Future<void> _editTitle(Template template) async {
    final lang = ref.read(languageProvider);
    final l10n = ref.read(l10nProvider);
    final placeholder =
        lang == '中文' ? '精彩集锦' : 'Awesome Highlight';
    final initial = template.title ?? '';
    final ctrl = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.editTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: placeholder,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancelBtn),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: Text(l10n.okBtn),
          ),
        ],
      ),
    );
    if (result == null) return;
    final title = result.trim().isEmpty ? placeholder : result.trim();
    final repo = ref.read(templateRepositoryProvider);
    await repo.save(template.copyWith(title: title));
    setState(_reload);
  }

  void _openEditor() {
    final category = switch (widget.type) {
      TemplateType.startup => TemplateCategory.startup,
      TemplateType.transition => TemplateCategory.transition,
      TemplateType.ending => TemplateCategory.ending,
      TemplateType.backgroundMusic => TemplateCategory.startup,
    };
    showDialog(
      context: context,
      builder: (_) => TemplateEditorDialog(initialCategory: category),
    );
  }

  Future<void> _addTemplate() async {
    final result = await FilePicker.platform.pickFiles(
      type: widget.type == TemplateType.backgroundMusic ? FileType.audio : FileType.video,
    );
    if (result != null &&
        result.files.isNotEmpty &&
        result.files.single.path != null) {
      final rawPath = result.files.single.path!;
      // Ensure absolute path — FilePicker may return relative on some platforms.
      final path = File(rawPath).absolute.path;
      final name = path.split(RegExp(r'[/\\]')).last;
      final repo = ref.read(templateRepositoryProvider);
      final template = await repo.save(Template(
        id: '',
        name: name,
        path: path,
        type: widget.type,
      ));
      ref
          .read(selectedTemplatesProvider.notifier)
          .select(widget.type, template.id);
      setState(_reload);
    }
  }

  Future<void> _deleteTemplate(String id, String name) async {
    final l10n = ref.read(l10nProvider);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteTemplateTitle),
        content: Text(l10n.deleteTemplateConfirm.replaceAll('{name}', name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l10n.cancelBtn)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.deleteAction),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final repo = ref.read(templateRepositoryProvider);
    final selectedId = ref.read(selectedTemplatesProvider)[widget.type];
    if (selectedId == id) {
      ref.read(selectedTemplatesProvider.notifier).select(widget.type, null);
    }
    await repo.delete(id);
    setState(_reload);
  }

  String _resolveProjectRoot() {
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

  String _resolveTemplatePath(Template template) {
    if (template.path.isNotEmpty) {
      if (File(template.path).isAbsolute) return template.path;
      return '${_resolveProjectRoot()}\\${template.path}';
    }
    return '';
  }

  Future<void> _playTemplate(Template template, AppStrings l10n) async {
    final title = template.title;
    final isTitleable = widget.type == TemplateType.startup ||
        widget.type == TemplateType.ending;
    final path = _resolveTemplatePath(template);

    // If the template has a title, generate a preview with the title overlaid.
    if (title != null && title.isNotEmpty && isTitleable) {
      final ffmpeg = await VideoProcessingService.findFfmpeg();
      if (ffmpeg != null) {
        final service = VideoProcessingService(ffmpegPath: ffmpeg);
        final tempDir = Directory.systemTemp;
        final previewPath =
            '${tempDir.path}${Platform.pathSeparator}hl_title_preview_'
            '${DateTime.now().millisecondsSinceEpoch}.mp4';
        final res = await service.overlayText(
          inputPath: path,
          outputPath: previewPath,
          text: title,
          // Startup/ending only (see isTitleable), so the plate center is the
          // right target; this also honours a saved top/bottom choice that the
          // preview used to ignore.
          yExpr: VideoProcessingService.textYExpr(template.textPosition),
        );
        if (!mounted) return;
        if (res.exitCode == 0) {
          unawaited(showDialog(
            context: context,
            builder: (_) => _VideoPlayDialog(filePath: previewPath, title: template.name),
          ));
          return;
        }
      }
    }

    if (!mounted) return;

    if (widget.type == TemplateType.backgroundMusic) {
      unawaited(showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(template.name),
          content: Text('${l10n.bgMusicFile}${path.split(RegExp(r'[/\\]')).last}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
          ],
        ),
      ));
      return;
    }

    unawaited(showDialog(
      context: context,
      builder: (_) => _VideoPlayDialog(filePath: path, title: template.name),
    ));
  }

  /// Derive localized title from template type.
  String _title(AppStrings l10n) {
    switch (widget.type) {
      case TemplateType.startup:
        return l10n.startupTemplate;
      case TemplateType.transition:
        return l10n.transitionTemplate;
      case TemplateType.ending:
        return l10n.endingTemplate;
      case TemplateType.backgroundMusic:
        return l10n.backgroundMusic;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final selectedId = ref.watch(selectedTemplatesProvider)[widget.type];
    final theme = Theme.of(context);

    ref.listen(templateRefreshProvider, (prev, next) {
      setState(_reload);
    });

    return CollapsiblePanel(
      title: _title(l10n),
      icon: widget.icon,
      iconColor: widget.iconColor,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.type != TemplateType.backgroundMusic)
            IconButton(
              icon: const Icon(Icons.tune, size: 16),
              tooltip: l10n.preview,
              onPressed: _openEditor,
              visualDensity: VisualDensity.compact,
              splashRadius: 16,
            ),
          IconButton(
            key: Key('template_add_${widget.type.name}'),
            icon: const Icon(Icons.add, size: 16),
            tooltip: l10n.addTemplate,
            onPressed: _addTemplate,
            visualDensity: VisualDensity.compact,
            splashRadius: 16,
          ),
        ],
      ),
      child: FutureBuilder<List<Template>>(
        future: _future,
        builder: (context, snapshot) {
          final templates = snapshot.data ?? [];

          if (templates.isNotEmpty && selectedId == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref
                  .read(selectedTemplatesProvider.notifier)
                  .select(widget.type, templates.first.id);
            });
          }

          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border(
                bottom: BorderSide(
                  color: theme.colorScheme.outline.withAlpha(60),
                ),
              ),
            ),
            child: templates.isEmpty
                ? Text(
                    l10n.noTemplates,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: templates.map((t) {
                      final isSelected = t.id == selectedId;
                      final resolvedPath = t.path.isNotEmpty
                          ? (File(t.path).isAbsolute ? t.path : _resolveTemplatePath(t))
                          : '';
                      return Tooltip(
                        message: resolvedPath.isNotEmpty ? resolvedPath : t.name,
                        waitDuration: const Duration(milliseconds: 400),
                        child: GestureDetector(
                          onTap: () => ref
                              .read(selectedTemplatesProvider.notifier)
                              .select(widget.type, t.id),
                          child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 3, horizontal: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.primaryContainer
                                    .withAlpha(80)
                                : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_unchecked,
                                size: 14,
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : Colors.white38,
                              ),
                              Icon(widget.icon,
                                  size: 14,
                                  color: theme.colorScheme.primary),
                              const SizedBox(width: 6),
                               Expanded(
                                 child: Text(
                                   t.name,
                                   style: const TextStyle(fontSize: 12),
                                   overflow: TextOverflow.ellipsis,
                                 ),
                               ),
                                if (widget.type == TemplateType.startup || widget.type == TemplateType.ending)
                                  IconButton(
                                    icon: const Icon(Icons.edit, size: 14),
                                    tooltip: l10n.editTitle,
                                    onPressed: () => _editTitle(t),
                                   visualDensity: VisualDensity.compact,
                                   splashRadius: 14,
                                   padding: EdgeInsets.zero,
                                   constraints: const BoxConstraints(
                                       minWidth: 28, minHeight: 28),
                                 ),
                               if (widget.type != TemplateType.backgroundMusic)
                                 IconButton(
                                   icon: const Icon(Icons.play_arrow, size: 16),
                                   tooltip: l10n.preview,
                                   onPressed: () => _playTemplate(t, l10n),
                                   visualDensity: VisualDensity.compact,
                                   splashRadius: 14,
                                   padding: EdgeInsets.zero,
                                   constraints: const BoxConstraints(
                                       minWidth: 28, minHeight: 28),
                                 ),
                               IconButton(
                                 icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                                 tooltip: l10n.removeFromList,
                                 onPressed: () => _deleteTemplate(t.id, t.name),
                                 visualDensity: VisualDensity.compact,
                                 splashRadius: 14,
                                 padding: EdgeInsets.zero,
                                 constraints: const BoxConstraints(
                                     minWidth: 28, minHeight: 28),
                               ),
                            ],
                          ),
                        ),
                      ),
                    );
                    }).toList(),
                  ),
          );
        },
      ),
    );
  }
}

/// Dialog that plays a video file using media_kit.
class _VideoPlayDialog extends StatefulWidget {
  final String filePath;
  final String title;

  const _VideoPlayDialog({required this.filePath, required this.title});

  @override
  State<_VideoPlayDialog> createState() => _VideoPlayDialogState();
}

class _VideoPlayDialogState extends State<_VideoPlayDialog> {
  Player? _player;
  VideoController? _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player!);
    _player!.open(Media(widget.filePath));
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              Flexible(
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Video(controller: _controller!),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}