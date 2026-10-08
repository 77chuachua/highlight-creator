import 'dart:io';
import 'package:flutter/material.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';

/// Dialog for configuring the zoom-in center point of remote timeslots.
///
/// Shows the first frame of each remote timeslot's video at the mark
/// position and lets the user click to set a center point.  When
/// "Apply to all" is checked (default), the first mark is applied to
/// all remote timeslots.
///
/// Returns a `Map<String, Offset>` mapping timeslot IDs to normalized
/// (0.0–1.0) center coordinates.  An empty map means no marks were set.
class ZoomInPointDialog extends StatefulWidget {
  final List<Timeslot> remoteTimeslots;
  final Map<String, String> sourcePaths;
  final String tempDir;
  final VideoProcessingService service;
  final AppStrings l10n;

  const ZoomInPointDialog({
    super.key,
    required this.remoteTimeslots,
    required this.sourcePaths,
    required this.tempDir,
    required this.service,
    required this.l10n,
  });

  @override
  State<ZoomInPointDialog> createState() => _ZoomInPointDialogState();
}

class _ZoomInPointDialogState extends State<ZoomInPointDialog> {
  int _currentIndex = 0;
  final Map<String, Offset> _marks = {};
  Offset? _currentMark;
  Offset? _mousePos;
  bool _applyToAll = true;
  bool _loading = true;
  String? _framePath;

  @override
  void initState() {
    super.initState();
    _loadFrame();
  }

  @override
  void dispose() {
    for (var i = 0; i < widget.remoteTimeslots.length; i++) {
      final f = File('${widget.tempDir}zoom_point_frame_$i.png');
      try { f.deleteSync(); } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _loadFrame() async {
    setState(() => _loading = true);
    final slot = widget.remoteTimeslots[_currentIndex];
    final sourcePath = widget.sourcePaths[slot.filename] ?? slot.filename;
    final timestamp = slot.inPointMs / 1000.0;
    final outputPath = '${widget.tempDir}zoom_point_frame_$_currentIndex.png';

    // Ensure the temp directory exists before extraction.
    final dir = Directory(widget.tempDir);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    await widget.service.extractFrame(
      sourcePath: sourcePath,
      timestampSecs: timestamp,
      outputPath: outputPath,
    );

    if (mounted) {
      setState(() {
        // Verify the frame file was actually created.
        _framePath = File(outputPath).existsSync() ? outputPath : null;
        _loading = false;
        _currentMark = _marks[slot.id];
      });
    }
  }

  void _setMark(Offset localPos, Size size) {
    setState(() {
      _currentMark = Offset(
        (localPos.dx / size.width).clamp(0.0, 1.0),
        (localPos.dy / size.height).clamp(0.0, 1.0),
      );
    });
  }

  void _onNext() {
    final slot = widget.remoteTimeslots[_currentIndex];
    if (_currentMark != null) {
      _marks[slot.id] = _currentMark!;
    }
    if (_currentIndex < widget.remoteTimeslots.length - 1) {
      setState(() {
        _currentIndex++;
        _currentMark = null;
        _framePath = null;
      });
      _loadFrame();
    }
  }

  void _onDone() {
    final slot = widget.remoteTimeslots[_currentIndex];
    if (_currentMark != null) {
      _marks[slot.id] = _currentMark!;
    }
    if (_applyToAll && _marks.isNotEmpty) {
      final firstMark = _marks.values.first;
      for (final s in widget.remoteTimeslots) {
        _marks[s.id] = firstMark;
      }
    }
    Navigator.of(context).pop(_marks);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = widget.l10n;
    final slot = widget.remoteTimeslots[_currentIndex];
    final isLast = _currentIndex >= widget.remoteTimeslots.length - 1;
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.zoomInPointTitle,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            Text(
              '${l10n.zoomTimeslotOf} ${_currentIndex + 1}/${widget.remoteTimeslots.length}: '
              '${slot.description.isNotEmpty ? slot.description : slot.filename}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 800,
              height: 450,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildImagePanel(l10n),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Checkbox(
                  value: _applyToAll,
                  onChanged: (v) => setState(() => _applyToAll = v ?? true),
                ),
                Text(l10n.zoomApplyToAll),
                const SizedBox(width: 16),
                FilledButton(
                  onPressed: (_applyToAll || isLast) ? null : _onNext,
                  child: Text(l10n.zoomNext),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _onDone,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                  ),
                  child: Text(l10n.zoomDone),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePanel(AppStrings l10n) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return MouseRegion(
          cursor: SystemMouseCursors.cell,
          onHover: (e) => setState(() => _mousePos = e.localPosition),
          onExit: (_) => setState(() => _mousePos = null),
          child: GestureDetector(
            onTapDown: (details) {
              _setMark(details.localPosition, constraints.biggest);
            },
            onSecondaryTapDown: (_) {
              setState(() => _currentMark = null);
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_framePath != null && File(_framePath!).existsSync())
                  Image.file(
                    File(_framePath!),
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  )
                else
                  Center(
                    child: Text(
                      l10n.zoomFailedLoadFrame,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  ),
                CustomPaint(
                  painter: _OverlayPainter(
                    mousePos: _mousePos,
                    mark: _currentMark,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final Offset? mousePos;
  final Offset? mark;

  _OverlayPainter({this.mousePos, this.mark});

  @override
  void paint(Canvas canvas, Size size) {
    if (mousePos != null) {
      final paint = Paint()
        ..color = Colors.white.withAlpha(128)
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset(0, mousePos!.dy),
        Offset(size.width, mousePos!.dy),
        paint,
      );
      canvas.drawLine(
        Offset(mousePos!.dx, 0),
        Offset(mousePos!.dx, size.height),
        paint,
      );
    }

    if (mark != null) {
      final markPx = Offset(mark!.dx * size.width, mark!.dy * size.height);
      canvas.drawCircle(markPx, 8, Paint()..color = Colors.red);
      final linePaint = Paint()
        ..color = Colors.red
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(markPx.dx - 12, markPx.dy),
        Offset(markPx.dx + 12, markPx.dy),
        linePaint,
      );
      canvas.drawLine(
        Offset(markPx.dx, markPx.dy - 12),
        Offset(markPx.dx, markPx.dy + 12),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      mousePos != old.mousePos || mark != old.mark;
}
