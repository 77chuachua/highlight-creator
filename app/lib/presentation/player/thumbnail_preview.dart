import 'package:flutter/material.dart';

/// Displays the relevant region of a thumbnail sprite sheet
/// when the user hovers or touches the scrub bar.
///
/// Phase 1: renders a placeholder grid that simulates the sprite
/// sheet layout. Phase 3 will replace this with actual image loading.
class ThumbnailPreview extends StatelessWidget {
  /// The total number of thumbnails in the sprite sheet.
  final int frameCount;

  /// The number of columns in the sprite grid.
  final int columns;

  /// Width of a single thumbnail in logical pixels.
  final double thumbWidth;

  /// Height of a single thumbnail in logical pixels.
  final double thumbHeight;

  /// The current position in the video as a fraction [0.0, 1.0].
  final double positionFraction;

  const ThumbnailPreview({
    super.key,
    required this.frameCount,
    required this.columns,
    this.thumbWidth = 120,
    this.thumbHeight = 68,
    this.positionFraction = 0.0,
  });

  int get _currentFrame {
    if (frameCount <= 0 || columns <= 0) return 0;
    return (positionFraction * (frameCount - 1)).round().clamp(0, frameCount - 1);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: thumbWidth + 8,
      height: thumbHeight + 8,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Thumbnail placeholder
          Expanded(
            child: Center(
              child: _buildFramePlaceholder(context),
            ),
          ),
          // Timestamp
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _formatTimestamp(),
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFramePlaceholder(BuildContext context) {
    // Phase 3: replace with actual sprite sheet region rendering.
    // For now, show a colored rectangle with frame number.
    final hue = (_currentFrame * 37) % 360;
    return Container(
      width: thumbWidth - 4,
      height: thumbHeight - 4,
      decoration: BoxDecoration(
        color: HSLColor.fromAHSL(0.7, hue.toDouble(), 0.5, 0.4).toColor(),
        borderRadius: BorderRadius.circular(2),
      ),
      child: Center(
        child: Text(
          '${_currentFrame + 1}',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _formatTimestamp() {
    // Placeholder timestamp based on frame index.
    // Phase 3: read actual timestamps from sprite metadata.
    final totalSeconds = _currentFrame * 2; // 2-second interval
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
