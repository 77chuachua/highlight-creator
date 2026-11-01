import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/services/ai_marking_service.dart';
import 'package:highlight_creator/services/goal_calibration.dart';

/// 「标定球门」: draw up to two boxes around the goals on one frame, save them
/// next to the app data, and (optionally) reuse them for every other video in
/// the same folder. See docs/ai_marking.md §球门标定.
///
/// Returns the number of boxes saved, or null when the user closed without
/// saving. The frame is 30 % into the source unless a calibration already
/// exists, in which case its `frameTimeMs` is reused so the old boxes line up.
Future<int?> openGoalCalibrationDialog(
  BuildContext context, {
  required String sourcePath,
}) {
  return showDialog<int>(
    context: context,
    builder: (_) => GoalCalibrationDialog(sourcePath: sourcePath),
  );
}

class GoalCalibrationDialog extends ConsumerStatefulWidget {
  const GoalCalibrationDialog({super.key, required this.sourcePath});

  final String sourcePath;

  @override
  ConsumerState<GoalCalibrationDialog> createState() =>
      _GoalCalibrationDialogState();
}

class _GoalCalibrationDialogState extends ConsumerState<GoalCalibrationDialog> {
  File? _frame;
  bool _loading = true;

  /// Fatal: no frame means there is nothing to draw on.
  String? _error;

  /// Non-fatal: the boxes are still on screen, the write just failed.
  String? _saveError;

  double _aspect = 16 / 9;
  List<NormRect> _rects = <NormRect>[];
  bool _applySiblings = false;
  int _frameTimeMs = 0;

  Offset? _dragStart;
  NormRect? _dragRect;

  AppStrings get _l10n => ref.read(l10nProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    final l10n = _l10n;
    final ffmpeg = await VideoProcessingService.findFfmpeg();
    if (!mounted) return;
    if (ffmpeg == null) {
      setState(() {
        _loading = false;
        _error = l10n.aiNoFfmpeg;
      });
      return;
    }

    final saved = GoalCalibration.load(widget.sourcePath);
    final durationMs =
        await VideoProcessingService.probeDurationMs(widget.sourcePath) ?? 0;
    final resolution =
        await VideoProcessingService.probeResolution(widget.sourcePath);
    // Reuse the saved frame when there is one, so the old boxes sit exactly
    // where the user drew them; otherwise 30 % into the match.
    final atMs = saved != null && saved.frameTimeMs > 0
        ? saved.frameTimeMs
        : (durationMs > 0 ? (durationMs * 0.3).round() : 0);

    try {
      final frame = await AiMarkingService(ffmpegPath: ffmpeg)
          .extractCalibrationFrame(sourcePath: widget.sourcePath, atMs: atMs);
      if (!mounted) return;
      setState(() {
        _frame = frame;
        _frameTimeMs = atMs;
        _rects = saved?.rects.toList() ?? <NormRect>[];
        if (resolution != null && resolution.$1 > 0 && resolution.$2 > 0) {
          _aspect = resolution.$1 / resolution.$2;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = l10n.goalCalibNoFrame;
      });
    }
  }

  void _commit(NormRect rect) {
    if (!rect.isUsable) return;
    setState(() {
      if (_rects.length < GoalCalibration.maxGoals) {
        _rects.add(rect);
      } else {
        // A third drag replaces 球门 2 (docs/ai_marking.md §球门标定).
        _rects[1] = rect;
      }
      _saveError = null;
    });
  }

  Future<void> _save() async {
    final count = _rects.length;
    final l10n = _l10n;
    final calibration = GoalCalibration(
      sourceKey: GoalCalibration.keyFor(widget.sourcePath),
      rects: _rects,
      frameTimeMs: _frameTimeMs,
      updatedAt: DateTime.now(),
    );
    if (!calibration.save()) {
      setState(() => _saveError = l10n.goalCalibSaveFailed);
      return;
    }
    if (_applySiblings) {
      GoalCalibration.applyToSiblings(widget.sourcePath);
    }
    if (!mounted) return;
    // The caller shows 「已标定 N 个球门」 on its own surface: a SnackBar would
    // sit behind this modal barrier until the AI dialog's barrier is gone.
    Navigator.pop(context, count);
  }

  Offset _normalized(Offset local, Size size) => Offset(
        size.width <= 0 ? 0.0 : local.dx / size.width,
        size.height <= 0 ? 0.0 : local.dy / size.height,
      );

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final theme = Theme.of(context);
    final ready = !_loading && _error == null && _frame != null;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.crop_free, size: 20),
          const SizedBox(width: 8),
          Text(l10n.goalCalibTitle),
        ],
      ),
      content: SizedBox(
        width: 760,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_saveError != null)
                _notice(theme, _saveError!, warning: true),
              if (_loading)
                SizedBox(
                  height: 140,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                        const SizedBox(height: 10),
                        Text(l10n.goalCalibLoading,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                )
              else if (_error != null)
                _notice(theme, _error!, warning: false)
              else ...[
                Text(l10n.goalCalibHint, style: theme.textTheme.bodySmall),
                const SizedBox(height: 8),
                AspectRatio(
                  aspectRatio: _aspect <= 0 ? 16 / 9 : _aspect,
                  child: _frameView(),
                ),
                const SizedBox(height: 10),
                if (_rects.isEmpty)
                  Text(
                    l10n.goalCalibEmpty,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  )
                else
                  for (var i = 0; i < _rects.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SelectableText(
                        _coordinates(l10n, i + 1, _rects[i]),
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'Consolas'),
                      ),
                    ),
                CheckboxListTile(
                  key: const Key('goal_calib_apply_siblings'),
                  value: _applySiblings,
                  onChanged: (value) =>
                      setState(() => _applySiblings = value ?? false),
                  title: Text(l10n.goalCalibApplySiblings,
                      style: theme.textTheme.bodySmall),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (ready)
          TextButton(
            key: const Key('goal_calib_clear'),
            onPressed: _rects.isEmpty
                ? null
                : () => setState(() {
                      _rects = <NormRect>[];
                      _saveError = null;
                    }),
            child: Text(l10n.goalCalibClear),
          ),
        if (ready)
          FilledButton(
            key: const Key('goal_calib_save'),
            onPressed: _rects.isEmpty ? null : _save,
            child: Text(l10n.goalCalibSave),
          ),
        TextButton(
          key: const Key('goal_calib_cancel'),
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }

  /// The frame with the committed boxes and the box being dragged on top.
  Widget _frameView() {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      Rect pixels(NormRect rect) => Rect.fromLTWH(
            rect.x * size.width,
            rect.y * size.height,
            rect.w * size.width,
            rect.h * size.height,
          );

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) {
          final start = _normalized(details.localPosition, size);
          setState(() {
            _dragStart = start;
            _dragRect = null;
          });
        },
        onPanUpdate: (details) {
          final start = _dragStart;
          if (start == null) return;
          final current = _normalized(details.localPosition, size);
          setState(() {
            _dragRect =
                NormRect.fromDrag(start.dx, start.dy, current.dx, current.dy);
          });
        },
        onPanEnd: (_) {
          final rect = _dragRect;
          setState(() {
            _dragStart = null;
            _dragRect = null;
          });
          if (rect != null) _commit(rect);
        },
        onPanCancel: () => setState(() {
          _dragStart = null;
          _dragRect = null;
        }),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.file(
              _frame!,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
            for (var i = 0; i < _rects.length; i++)
              _box(pixels(_rects[i]), '${i + 1}'),
            if (_dragRect != null)
              _box(
                pixels(_dragRect!),
                '${_rects.length < GoalCalibration.maxGoals ? _rects.length + 1 : GoalCalibration.maxGoals}',
              ),
          ],
        ),
      );
    });
  }

  Widget _box(Rect rect, String label) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: math.max(rect.width, 2.0),
      height: math.max(rect.height, 2.0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.orangeAccent, width: 2),
          color: Colors.orangeAccent.withAlpha(18),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            color: Colors.orangeAccent,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// `球门 1: x=0.123 y=0.456 w=0.789 h=0.012` — 3 decimals for eyeballing.
  String _coordinates(AppStrings l10n, int index, NormRect rect) =>
      '${l10n.goalCalibGoalLabel(index)}: '
      'x=${rect.x.toStringAsFixed(3)} y=${rect.y.toStringAsFixed(3)} '
      'w=${rect.w.toStringAsFixed(3)} h=${rect.h.toStringAsFixed(3)}';

  Widget _notice(ThemeData theme, String text, {required bool warning}) {
    final color = warning ? Colors.orangeAccent : theme.colorScheme.error;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        border: Border.all(color: color.withAlpha(120)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(warning ? Icons.warning_amber : Icons.error_outline,
              size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(text,
                style: TextStyle(fontSize: 12, color: color, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
