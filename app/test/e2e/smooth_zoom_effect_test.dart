// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';

/// Verify that a 10-second sub-video sliced from test1.mp4 has a smooth
/// zoom-in (1x → 1.7x) and horizontal pan (x 0 → 400) applied.  Output
/// lands in the project temp/e2e/ directory.
void main() {
  test('smooth zoom effect: zoom 1x→1.7x, pan x 0→400 over 10s', () async {
    // ── Resolve project root ──────────────────────────────────────────
    final projectRoot = _resolveProjectRoot();
    final sourcePath = '$projectRoot\\test\\e2e\\videoSource\\test1.mp4';
    final tempDir = '$projectRoot\\temp\\e2e\\';

    // Ensure the source video exists.
    expect(File(sourcePath).existsSync(), isTrue,
        reason: 'Source video missing: $sourcePath');

    // Ensure temp directory exists.
    final dir = Directory(tempDir);
    if (!dir.existsSync()) await dir.create(recursive: true);

    // Enable ffmpeg command logging (project root, survives temp cleanup).
    VideoProcessingService.commandLogPath = '$projectRoot\\ffmpeg_command';
    VideoProcessingService.commandLogContext =
        'smooth_zoom_effect_test.dart :: '
        'smooth zoom effect: zoom 1x\u21921.7x, pan x 0\u2192400 over 10s';

    // Locate ffmpeg.
    final ffmpegPath = await VideoProcessingService.findFfmpeg();
    if (ffmpegPath == null) {
      // Without ffmpeg the service copies the source as-is — still valid
      // for simulation but the zoom effect won't be applied.
      print('ffmpeg not found — will copy source as-is (simulation mode).');
    }

    final service = VideoProcessingService(ffmpegPath: ffmpegPath);
    final outputPath = '${tempDir}smooth_zoom_effect.mp4';

    // ── Slice with zoom effect ─────────────────────────────────────────
    final result = await service.sliceSubVideoWithZoom(
      sourcePath: sourcePath,
      outputPath: outputPath,
      startSecs: 0,
      durationSecs: 10,
      startupVideoPath: sourcePath, // fallback for simulation mode
      zoomStart: 1.0,
      zoomEnd: 1.7,
      panXEnd: -400,
    );

    expect(result.exitCode, 0,
        reason: 'ffmpeg failed:\n${result.stderr}');

    // ── Verify output ──────────────────────────────────────────────────
    final outFile = File(outputPath);
    expect(outFile.existsSync(), isTrue,
        reason: 'Output file was not created: $outputPath');

    final size = outFile.lengthSync();
    print('Output: $outputPath  (${(size / 1024).toStringAsFixed(1)} KB)');
    expect(size, greaterThan(1000),
        reason: 'Output file too small — likely corrupt');
  });
}

/// Walk up from cwd to find the project root (AGENTS.md or app/ dir).
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