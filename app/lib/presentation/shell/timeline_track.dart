import 'dart:io' show File;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/presentation/shell/timeslot_table.dart';

/// Maps a global timeline position to `(segment index, local ms)` for
/// seeking across playlist segments. [globalMs] is clamped to the total.
({int index, int localMs}) globalToLocal(List<int> durationsMs, int globalMs) {
  final total = durationsMs.fold(0, (a, b) => a + b);
  final ms = globalMs.clamp(0, total);
  var acc = 0;
  for (var i = 0; i < durationsMs.length; i++) {
    final d = durationsMs[i];
    if (ms < acc + d || i == durationsMs.length - 1) {
      return (index: i, localMs: (ms - acc).clamp(0, d));
    }
    acc += d;
  }
  return (index: 0, localMs: 0);
}

/// Shared scrub track for the auto-gen timeline and the main window: a
/// seconds ruler on top and a zoomable/scrollable preview bar below it, with
/// timeslot rects (draggable edge handles) and a white playhead line.
///
/// Rendering and the drag interaction are owned here; playback and seek
/// responsibility is delegated to the host via callbacks so the same widget
/// drives both the auto-gen playlist player and the main single-video player.
class TimelineTrack extends ConsumerStatefulWidget {
  final List<VideoSource> sources;
  final List<int> durationsMs;
  final List<String?> previewPaths;
  final int globalPositionMs;
  final double pxPerSec;
  final double rulerHeight;
  final double previewBarHeight;
  final double previewImageHeightRatio;

  /// Live playback position for the playhead, decoupled from provider state so
  /// position ticks only repaint the thin playhead line instead of rebuilding
  /// the whole track (4K lag regression when the tracker is expanded).
  final ValueNotifier<Duration>? livePosition;

  /// Source-segment the [livePosition] belongs to (-1 = none). Rebuilt only
  /// when the currently loaded video changes.
  final int positionSegment;

  /// Maps a timeslot to the source-segment index it belongs to (-1 if none).
  final int Function(Timeslot s) segmentOf;

  /// Click anywhere on the track (background or a timeslot body): seek to the
  /// exact global ms under the pointer (host decides pause).
  final void Function(int globalMs) onTrackTap;

  /// Commit of a drag resize: host persists the slot and seeks the playhead.
  final void Function(Timeslot s, int newInMs, int newOutMs, int seekMs)
      onCommitDrag;

  const TimelineTrack({
    super.key,
    required this.sources,
    required this.durationsMs,
    required this.previewPaths,
    required this.globalPositionMs,
    required this.segmentOf,
    required this.onTrackTap,
    required this.onCommitDrag,
    this.livePosition,
    this.positionSegment = -1,
    this.pxPerSec = 30,
    this.rulerHeight = 24,
    this.previewBarHeight = 48,
    this.previewImageHeightRatio = 0.8,
  });

  @override
  ConsumerState<TimelineTrack> createState() => _TimelineTrackState();
}

class _TimelineTrackState extends ConsumerState<TimelineTrack> {
  final ScrollController _trackScroll = ScrollController();
  double _viewportW = 0;
  double _lastScrollOffset = -1;
  ValueNotifier<Duration>? _wiredPosition;

  // Live drag state while a slot handle is being dragged.
  String? _draggingSlotId;
  String? _dragSide; // 'start' or 'end'
  Timeslot? _dragOriginalSlot;
  double _dragStartPx = 0;
  double _dragLastDeltaPx = 0;
  double _dragLastLocalPx = 0;

  int get _totalMs => widget.durationsMs.fold(0, (a, b) => a + b);

  int _offsetMs(int i) {
    var g = 0;
    for (var k = 0; k < i && k < widget.durationsMs.length; k++) {
      g += widget.durationsMs[k];
    }
    return g;
  }

  /// Global playhead ms for a live `position`; falls back to the static
  /// global position (widget.globalPositionMs) when no live feed is wired.
  int _globalMs(Duration position) {
    final seg = widget.positionSegment;
    final offset = (seg >= 0 && seg < widget.sources.length)
        ? _offsetMs(seg)
        : 0;
    return (offset + position.inMilliseconds).clamp(0, _totalMs);
  }

  @override
  void initState() {
    super.initState();
    _wirePosition();
  }

  @override
  void didUpdateWidget(covariant TimelineTrack old) {
    super.didUpdateWidget(old);
    if (old.livePosition != widget.livePosition) _wirePosition();
  }

  void _wirePosition() {
    _wiredPosition?.removeListener(_onLivePosition);
    final pos = widget.livePosition;
    _wiredPosition = pos;
    if (pos == null) return;
    _onPositionChanged(_globalMs(pos.value));
    pos.addListener(_onLivePosition);
  }

  void _onLivePosition() {
    _onPositionChanged(_globalMs(widget.livePosition!.value));
  }

  @override
  void dispose() {
    _wiredPosition?.removeListener(_onLivePosition);
    _trackScroll.dispose();
    super.dispose();
  }

  // ── Playhead distance-based auto-scroll ────────────────
  void _onPositionChanged(int globalPositionMs) {
    if (!_trackScroll.hasClients) return;
    final posPx = globalPositionMs / 1000.0 * widget.pxPerSec;
    final offset = _trackScroll.offset;
    final viewportW = _trackScroll.position.viewportDimension;
    final maxScroll = _trackScroll.position.maxScrollExtent;
    final margin = viewportW * 0.15;
    // The playhead left the viewport entirely (e.g. seeking from video 1 to
    // video 10): snap straight to it instead of stepping half a viewport per
    // frame, which used to take ~10s of scrolling (issues.md).
    if (posPx < offset || posPx > offset + viewportW) {
      final target = (posPx - viewportW * 0.1).clamp(0.0, maxScroll);
      _lastScrollOffset = target;
      _trackScroll.jumpTo(target);
      return;
    }
    double? target;
    if (posPx > offset + viewportW - margin) {
      target = (offset + viewportW * 0.5).clamp(0.0, maxScroll);
    } else if (posPx < offset + margin) {
      target = (offset - viewportW * 0.5).clamp(0.0, maxScroll);
    }
    if (target != null && (target - _lastScrollOffset).abs() > 10) {
      _lastScrollOffset = target;
      _trackScroll.jumpTo(target);
    }
  }

  void _onTrackTapDown(TapDownDetails d) {
    if (_draggingSlotId != null) return;
    final totalMs = _totalMs;
    if (totalMs <= 0) return;
    widget.onTrackTap((d.localPosition.dx / widget.pxPerSec * 1000).round());
  }

  // ── Drag handles ─────────────────────────────────────
  void _onHandlePanStart(Timeslot slot, String side, DragStartDetails d) {
    _draggingSlotId = slot.id;
    _dragSide = side;
    _dragStartPx = d.globalPosition.dx;
    _dragOriginalSlot = slot;
    _dragLastDeltaPx = 0;
    setState(() {});
  }

  void _onHandlePanUpdate(DragUpdateDetails d) {
    if (_draggingSlotId == null || _dragOriginalSlot == null) return;
    _dragLastDeltaPx = d.globalPosition.dx - _dragStartPx;
    _dragLastLocalPx = d.localPosition.dx;
    setState(() {});
  }

  void _commitDrag() {
    final orig = _dragOriginalSlot;
    final side = _dragSide;
    if (_draggingSlotId == null || orig == null || side == null) return;
    final deltaMs = (_dragLastDeltaPx / widget.pxPerSec * 1000).round();
    final seg = widget.segmentOf(orig);
    if (seg < 0 || deltaMs == 0) {
      _resetDrag();
      return;
    }
    final segDurMs = widget.durationsMs[seg];
    final segOffset = _offsetMs(seg);

    int newInMs;
    int newOutMs;
    if (side == 'start') {
      newInMs = (orig.inPointMs + deltaMs).clamp(0, segDurMs - 100);
      newOutMs = orig.outPointMs;
    } else {
      newInMs = orig.inPointMs;
      newOutMs = (orig.outPointMs + deltaMs)
          .clamp(orig.inPointMs + 100, segDurMs);
    }
    final seekMs =
        segOffset + newInMs + (_dragLastLocalPx / widget.pxPerSec * 1000).round();
    _resetDrag();
    widget.onCommitDrag(orig, newInMs, newOutMs, seekMs.clamp(0, _totalMs));
  }

  void _resetDrag() {
    _draggingSlotId = null;
    _dragSide = null;
    _dragOriginalSlot = null;
    _dragLastDeltaPx = 0;
    _dragLastLocalPx = 0;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        _viewportW = c.maxWidth;
        final trackW =
            math.max(_viewportW, _totalMs / 1000.0 * widget.pxPerSec);
        // Without a live feed (e.g. tests / static position) auto-scroll once
        // per build; with a live feed the position listener handles it.
        if (widget.livePosition == null) {
          final posMs = widget.globalPositionMs;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _onPositionChanged(posMs);
          });
        }
        return Scrollbar(
          controller: _trackScroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _trackScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: trackW,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildRuler(),
                  _buildPreviewBar(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRuler() {
    final totalSec = _totalMs / 1000.0;
    if (totalSec <= 0) return SizedBox(height: widget.rulerHeight);
    // ponytail: ceiling = one Positioned+Text per tick; at 1s unit on very
    // long videos this is thousands of widgets; upgrade path is CustomPaint.
    const unitSecs = 1;
    return SizedBox(
      height: widget.rulerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = 0; i < widget.sources.length; i++)
            for (var t = 0.0; t <= widget.durationsMs[i] / 1000.0; t += unitSecs)
              Positioned(
                left: (_offsetMs(i) + t * 1000) / 1000.0 * widget.pxPerSec,
                top: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _fmtSecs(t),
                      style: const TextStyle(fontSize: 8, color: Colors.white54),
                    ),
                    Container(width: 1, height: 4, color: Colors.white38),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildPreviewBar() {
    final totalMs = _totalMs;
    final trackW = math.max(_viewportW, totalMs / 1000.0 * widget.pxPerSec);
    final previewImageHeight =
        widget.previewBarHeight * widget.previewImageHeightRatio;
    final slots = ref.watch(recordProvider).timeslots;

    final slotRects = <Widget>[];
    for (final s in slots) {
      final seg = widget.segmentOf(s);
      if (seg < 0 || totalMs <= 0) continue;
      final segOffset = _offsetMs(seg);

      int inMs = s.inPointMs;
      int elapseMs = s.elapse > 0 ? s.elapse : (s.outPointMs - s.inPointMs);
      if (_draggingSlotId == s.id && _dragOriginalSlot != null) {
        final orig = _dragOriginalSlot!;
        final deltaMs = (_dragLastDeltaPx / widget.pxPerSec * 1000).round();
        final origSeg = widget.segmentOf(orig);
        if (origSeg >= 0) {
          final segDur = widget.durationsMs[origSeg];
          if (_dragSide == 'start') {
            inMs = (orig.inPointMs + deltaMs).clamp(0, segDur - 100);
            elapseMs = (orig.outPointMs - inMs).clamp(100, segDur - inMs);
          } else {
            final newOut = (orig.outPointMs + deltaMs)
                .clamp(orig.inPointMs + 100, segDur);
            inMs = orig.inPointMs;
            elapseMs = (newOut - orig.inPointMs)
                .clamp(100, segDur - orig.inPointMs);
          }
        }
      }

      final leftPx = (segOffset + inMs) / 1000.0 * widget.pxPerSec;
      final widthPx = math.max(2.0, elapseMs / 1000.0 * widget.pxPerSec);
      final color =
          TimeslotTable.colors[s.colorIndex % TimeslotTable.colors.length];
      final handleW = math.max(6.0, math.min(8.0, widthPx * 0.15));

      slotRects.add(
        Positioned(
          left: leftPx,
          top: 0,
          bottom: 0,
          width: widthPx,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (d) {
              final isLeft = d.localPosition.dx < handleW;
              final isRight = d.localPosition.dx > widthPx - handleW;
              final side = isLeft ? 'start' : (isRight ? 'end' : null);
              if (side != null) _onHandlePanStart(s, side, d);
            },
            onPanUpdate: _onHandlePanUpdate,
            onPanEnd: (_) => _commitDrag(),
            // Click on a timeslot seeks to the EXACT clicked time, same as
            // clicking the track background (issues.md).
            onTapDown: (d) {
              if (_draggingSlotId != null) return;
              if (totalMs <= 0) return;
              final segMs = segOffset + inMs;
              final clickedMs =
                  segMs + (d.localPosition.dx / widget.pxPerSec * 1000).round();
              widget.onTrackTap(clickedMs.clamp(0, totalMs));
            },
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: color.withAlpha(102),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: handleW,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(178),
                        border: const Border(
                          right: BorderSide(color: Colors.white24, width: 1),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: handleW,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(178),
                        border: const Border(
                          left: BorderSide(color: Colors.white24, width: 1),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: widget.previewBarHeight,
      width: trackW,
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _onTrackTapDown,
              child: Container(color: Colors.grey.shade700),
            ),
          ),
          for (var i = 0; i < widget.sources.length; i++)
            Positioned(
              left: _offsetMs(i) / 1000.0 * widget.pxPerSec,
              top: (widget.previewBarHeight - previewImageHeight) / 2,
              width: widget.durationsMs[i] / 1000.0 * widget.pxPerSec,
              height: previewImageHeight,
              child: IgnorePointer(
                child: widget.previewPaths.length > i &&
                        widget.previewPaths[i] != null
                    ? Image.file(
                        File(widget.previewPaths[i]!),
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade600,
                          child: const Icon(Icons.video_file,
                              size: 16, color: Colors.white54),
                        ),
                      )
                    : Container(
                        color: Colors.grey.shade600,
                        child: const Icon(Icons.video_file,
                            size: 16, color: Colors.white54),
                      ),
              ),
            ),
          ...slotRects,
          _buildPlayhead(totalMs, trackW),
        ],
      ),
    );
  }

  /// The white playhead line. When a live position feed is wired, only this
  /// thin line rebuilds on every tick instead of the whole track (fixes the
  /// 4K lag that appeared when the tracker bar was expanded).
  Widget _buildPlayhead(int totalMs, double trackW) {
    Widget lineFor(int globalMs) {
      final posPx = totalMs > 0 ? globalMs / 1000.0 * widget.pxPerSec : 0.0;
      return Positioned(
        left: posPx.clamp(0.0, trackW - 2.0),
        top: 0,
        bottom: 0,
        width: 2,
        child: IgnorePointer(
          child: Container(color: Colors.white),
        ),
      );
    }

    final live = widget.livePosition;
    if (live == null) {
      return lineFor(widget.globalPositionMs);
    }
    return ValueListenableBuilder<Duration>(
      valueListenable: live,
      builder: (context, pos, _) => lineFor(_globalMs(pos)),
    );
  }

  String _fmtSecs(double secs) {
    final s = secs.round();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final r = s % 60;
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}'
        : '$m:${r.toString().padLeft(2, '0')}';
  }
}