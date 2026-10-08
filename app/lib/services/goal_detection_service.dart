import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Axis-aligned goal candidate box in full-resolution frame pixels.
class GoalBox {
  final int x;
  final int y;
  final int w;
  final int h;
  final double score;

  const GoalBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.score,
  });

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h, 'score': score};
}

/// Result of a goal detection run: extracted frame, marked frame and JSON.
class GoalDetectionResult {
  final String framePath;
  final String markedPath;
  final String jsonPath;
  final double timestampSecs;
  final int frameWidth;
  final int frameHeight;
  final List<GoalBox> goals;

  const GoalDetectionResult({
    required this.framePath,
    required this.markedPath,
    required this.jsonPath,
    required this.timestampSecs,
    required this.frameWidth,
    required this.frameHeight,
    required this.goals,
  });
}

/// Standalone service that locates football/hockey goals in a video frame.
///
/// Extracts one frame with ffmpeg, runs a pure-Dart white-net heuristic
/// ([detectGoalsInRgb]) on a downscaled RGB24 copy, then marks the detected
/// goal boxes on the full-resolution frame via ffmpeg `drawbox` and writes
/// the coordinates to JSON. No ML model, no third-party dependencies.
class GoalDetectionService {
  final String ffmpegPath;

  const GoalDetectionService({required this.ffmpegPath});

  static const int _aw = 1920;
  static const int _ah = 1080;
  static const int _cell = 16;

  /// Extract a frame at [timestampSecs], detect goals, mark them, and write
  /// `frame_*.png`, `frame_*_marked.png` and `goal_result.json` to [outputDir].
  Future<GoalDetectionResult> detectGoal({
    required String videoPath,
    required String outputDir,
    double timestampSecs = 10.0,
    int maxGoals = 2,
  }) async {
    if (!File(videoPath).existsSync()) {
      throw FileSystemException('Video file not found', videoPath);
    }
    Directory(outputDir).createSync(recursive: true);

    final tag = timestampSecs.toStringAsFixed(1);
    final sep = Platform.pathSeparator;
    final framePath = '$outputDir${sep}frame_${tag}s.png';
    final rawPath = '$outputDir${sep}frame_${tag}s.raw';
    final markedPath = '$outputDir${sep}frame_${tag}s_marked.png';
    final jsonPath = '$outputDir${sep}goal_result.json';

    await _ffmpeg(['-y', '-v', 'error', '-ss', tag, '-i', videoPath,
      '-frames:v', '1', framePath]);
    await _ffmpeg(['-y', '-v', 'error', '-ss', tag, '-i', videoPath,
      '-frames:v', '1', '-vf', 'scale=$_aw:$_ah',
      '-f', 'rawvideo', '-pix_fmt', 'rgb24', rawPath]);

    final rgb = File(rawPath).readAsBytesSync();
    try {
      File(rawPath).deleteSync();
    } catch (_) {}
    if (rgb.length != _aw * _ah * 3) {
      throw StateError('Unexpected raw frame size: ${rgb.length} bytes');
    }

    final detected = detectGoalsInRgb(rgb, _aw, _ah).take(maxGoals).toList();

    final size = _pngSize(File(framePath).readAsBytesSync());
    final sx = size.$1 / _aw;
    final sy = size.$2 / _ah;
    final goals = detected
        .map((b) => GoalBox(
              x: (b.x * sx).round(),
              y: (b.y * sy).round(),
              w: (b.w * sx).round(),
              h: (b.h * sy).round(),
              score: b.score,
            ))
        .toList();

    final boxes = <String>[];
    for (var i = 0; i < goals.length; i++) {
      final b = goals[i];
      final color = i == 0 ? 'red' : 'yellow';
      boxes.add('drawbox=x=${b.x}:y=${b.y}:w=${b.w}:h=${b.h}:'
          'color=$color@0.9:t=${(size.$1 / 480).round()}');
    }
    if (boxes.isEmpty) {
      File(framePath).copySync(markedPath);
    } else {
      await _ffmpeg(['-y', '-v', 'error', '-i', framePath,
        '-vf', boxes.join(','), markedPath]);
    }

    final json = {
      'video': videoPath,
      'timestamp_secs': timestampSecs,
      'frame_width': size.$1,
      'frame_height': size.$2,
      'goals': goals.map((b) => b.toJson()).toList(),
      'frame': framePath,
      'marked': markedPath,
    };
    File(jsonPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(json));

    return GoalDetectionResult(
      framePath: framePath,
      markedPath: markedPath,
      jsonPath: jsonPath,
      timestampSecs: timestampSecs,
      frameWidth: size.$1,
      frameHeight: size.$2,
      goals: goals,
    );
  }

  Future<void> _ffmpeg(List<String> args) async {
    final r = await Process.run(ffmpegPath, args);
    final out = args.last;
    if (r.exitCode != 0 || !File(out).existsSync()) {
      throw StateError('ffmpeg failed (${r.exitCode}): ${r.stderr}');
    }
  }

  /// Read width/height from a PNG IHDR chunk.
  static (int, int) _pngSize(Uint8List b) {
    final bd = ByteData.sublistView(b);
    return (bd.getUint32(16), bd.getUint32(20));
  }

  /// Pure heuristic over RGB24 pixels: a goal net is a two-dimensional blob
  /// of white mesh — denser than pitch lines/text (thin), sparser than
  /// boards/lights (solid white).
  ///
  /// ponytail: ceiling = white-mesh assumption breaks for dark/colored nets
  /// and cluttered daylight scenes; upgrade path is a trained detector
  /// (e.g. YOLO/ONNX) fed the same extracted frame.
  static List<GoalBox> detectGoalsInRgb(Uint8List rgb, int width, int height) {
    final white = Uint8List(width * height);
    for (var i = 0; i < width * height; i++) {
      final r = rgb[i * 3], g = rgb[i * 3 + 1], b = rgb[i * 3 + 2];
      final mn = r < g ? (r < b ? r : b) : (g < b ? g : b);
      final mx = r > g ? (r > b ? r : b) : (g > b ? g : b);
      if (mn > 150 && mx - mn < 60) white[i] = 1;
    }

    final gw = width ~/ _cell;
    final gh = height ~/ _cell;
    final dens = Float32List(gw * gh);
    for (var cy = 0; cy < gh; cy++) {
      for (var cx = 0; cx < gw; cx++) {
        var c = 0;
        for (var y = cy * _cell; y < (cy + 1) * _cell; y++) {
          for (var x = cx * _cell; x < (cx + 1) * _cell; x++) {
            c += white[y * width + x];
          }
        }
        dens[cy * gw + cx] = c / (_cell * _cell);
      }
    }

    // Erode (all 4 neighbors must be net) so thin horizon structures — lit
    // fence strips, pitch lines, light shafts — cannot chain the net blob
    // into one giant component; dilate back so a distant goal's fragmented
    // core reconnects.
    final eroded = Uint8List(gw * gh);
    for (var cy = 1; cy < gh - 1; cy++) {
      for (var cx = 1; cx < gw - 1; cx++) {
        final i = cy * gw + cx;
        if (_netCell(dens[i]) &&
            _netCell(dens[i - 1]) &&
            _netCell(dens[i + 1]) &&
            _netCell(dens[i - gw]) &&
            _netCell(dens[i + gw])) {
          eroded[i] = 1;
        }
      }
    }
    final core = Uint8List(gw * gh);
    for (var cy = 0; cy < gh; cy++) {
      for (var cx = 0; cx < gw; cx++) {
        final i = cy * gw + cx;
        if (eroded[i] == 1) {
          core[i] = 1;
          continue;
        }
        for (var dy = -1; dy <= 1 && core[i] == 0; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = cx + dx, ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
            if (eroded[ny * gw + nx] == 1) {
              core[i] = 1;
              break;
            }
          }
        }
      }
    }

    final seen = Uint8List(gw * gh);
    final out = <GoalBox>[];
    for (var s = 0; s < gw * gh; s++) {
      if (seen[s] == 1 || core[s] == 0) {
        seen[s] = 1;
        continue;
      }

      var minX = gw, maxX = 0, minY = gh, maxY = 0;
      final stack = [s];
      seen[s] = 1;
      while (stack.isNotEmpty) {
        final c = stack.removeLast();
        final cx = c % gw, cy = c ~/ gw;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = cx + dx, ny = cy + dy;
            if (nx < 0 || ny < 0 || nx >= gw || ny >= gh) continue;
            final n = ny * gw + nx;
            if (seen[n] == 0 && core[n] == 1) {
              seen[n] = 1;
              stack.add(n);
            }
          }
        }
      }

      // Recover the net border shaved off by the erosion.
      minX = (minX - 1).clamp(0, gw - 1);
      maxX = (maxX + 1).clamp(0, gw - 1);
      minY = (minY - 1).clamp(0, gh - 1);
      maxY = (maxY + 1).clamp(0, gh - 1);
      final bw = maxX - minX + 1, bh = maxY - minY + 1;
      if (bw < 3 || bh < 3) continue;
      // Goals sit in the horizon band, never in sky or watermark strip.
      final cyPx = (minY + maxY + 1) / 2 * _cell;
      if (cyPx < height * 0.30 || cyPx > height * 0.92) continue;

      var wc = 0, rh = 0, rv = 0;
      for (var y = minY * _cell; y < (maxY + 1) * _cell; y++) {
        var prev = false;
        for (var x = minX * _cell; x < (maxX + 1) * _cell; x++) {
          final isW = white[y * width + x] == 1;
          if (isW) {
            wc++;
            if (!prev) rh++;
          }
          prev = isW;
        }
      }
      for (var x = minX * _cell; x < (maxX + 1) * _cell; x++) {
        var prev = false;
        for (var y = minY * _cell; y < (maxY + 1) * _cell; y++) {
          final isW = white[y * width + x] == 1;
          if (isW && !prev) rv++;
          prev = isW;
        }
      }
      final pd = wc / ((bw * _cell) * (bh * _cell));
      // Solid white objects (boards, lights) saturate; nets sit mid-range.
      if (wc == 0 || pd < 0.08 || pd > 0.60) continue;

      // Near goal: one big two-dimensional white blob with mesh rhythm in
      // both directions. Distant goal: small, with a strong vertical mesh
      // rhythm (boards/text have few long runs).
      final near = bw >= 8 && bh >= 8 && rh / wc >= 0.09;
      final far = bw <= 8 && bh <= 8 && rv / wc >= 0.30;
      if (!near && !far) continue;

      out.add(GoalBox(
        x: minX * _cell,
        y: minY * _cell,
        w: bw * _cell,
        h: bh * _cell,
        score: bw * bh * pd * (near ? 10.0 : 1.0),
      ));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  static bool _netCell(double d) => d >= 0.12;
}
