import 'dart:io' show Directory, File;

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';

/// Issues.md: the source list used to show "0s" for every file. The metadata
/// must come from ffprobe (duration, resolution, codec, fps).
void main() {
  test('probeVideoInfo returns real metadata for a fixture video', () async {
    final projectRoot = _resolveProjectRoot();
    final sourcePath = '$projectRoot\\test\\e2e\\videoSource\\test1.mp4';
    expect(File(sourcePath).existsSync(), isTrue,
        reason: 'Source video missing: $sourcePath');

    final info = await VideoProcessingService.probeVideoInfo(sourcePath);
    expect(info, isNotNull, reason: 'ffprobe should extract metadata');
    expect(info!.durationMs, greaterThan(0),
        reason: 'duration must not be 0s');
    expect(info.width, greaterThan(0), reason: 'width must be probed');
    expect(info.height, greaterThan(0), reason: 'height must be probed');
    expect(info.codecName, isNotEmpty, reason: 'codec name must be probed');
    expect(info.fps, greaterThan(0), reason: 'fps must be probed');
  });

  test('probeVideoInfo returns null for a missing file', () async {
    final info = await VideoProcessingService.probeVideoInfo(
        'C:\\nonexistent\\video.mp4');
    expect(info, isNull);
  });
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