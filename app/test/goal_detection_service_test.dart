import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/services/goal_detection_service.dart';

void main() {
  test('detects white net mesh, ignores lines, boards and lights', () {
    const w = 960, h = 540;
    final rgb = Uint8List(w * h * 3);
    void px(int x, int y, int r, int g, int b) {
      final i = (y * w + x) * 3;
      rgb[i] = r;
      rgb[i + 1] = g;
      rgb[i + 2] = b;
    }

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        px(x, y, 30, 100, 40);
      }
    }
    // Goal net mesh at (600,250)-(750,400): 1px white line every 4px.
    for (var y = 250; y < 400; y++) {
      for (var x = 600; x < 750; x++) {
        if (x % 4 == 0 || y % 4 == 0) px(x, y, 240, 240, 240);
      }
    }
    // Pitch line (thin, must be ignored).
    for (var y = 470; y < 473; y++) {
      for (var x = 0; x < w; x++) {
        px(x, y, 245, 245, 245);
      }
    }
    // Solid white board (must be ignored).
    for (var y = 260; y < 320; y++) {
      for (var x = 100; x < 200; x++) {
        px(x, y, 250, 250, 250);
      }
    }
    // Floodlight in the sky (must be ignored).
    for (var y = 60; y < 90; y++) {
      for (var x = 470; x < 500; x++) {
        px(x, y, 255, 255, 255);
      }
    }

    final goals = GoalDetectionService.detectGoalsInRgb(rgb, w, h);
    expect(goals.length, 1);
    final g = goals.first;
    expect(g.x, lessThanOrEqualTo(600 + 12));
    expect(g.y, lessThanOrEqualTo(250 + 12));
    expect(g.x + g.w, greaterThanOrEqualTo(750 - 12));
    expect(g.y + g.h, greaterThanOrEqualTo(400 - 12));
  });
}
