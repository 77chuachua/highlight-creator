// ignore_for_file: avoid_print
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';
import 'package:media_kit/media_kit.dart';

/// Regression for `Assertion failed: "[Player] has been disposed"` in
/// `loadVideo` (issues.md). Two autoplay listeners (the view-model's own
/// `completed` listener and `SourceFileList._advanceToNext`) can call
/// `loadVideo` at the same time. Both used to `await _player?.dispose()` on the
/// same live Player, and the second dispose threw.
///
/// Non-existent paths are used on purpose: `loadVideo` still creates the
/// Player and takes the disposal path without needing real media decoding.
/// media_kit's native video plugin / event loop is absent under `flutter test`,
/// so all errors are collected with [runZonedGuarded] and only the
/// double-dispose assertion is asserted on.
void main() {
  setUpAll(MediaKit.ensureInitialized);

  test('overlapping loadVideo calls do not dispose the same Player twice',
      () async {
    final container = ProviderContainer();
    final vm = container.read(videoPlayerProvider.notifier);
    final errors = <Object>[];
    var hadPlayer = false;

    await runZonedGuarded(() async {
      // First load creates a live Player (open fails, but the player exists).
      await vm.loadVideo(r'Z:\highlight_creator_missing\a.mp4');
      hadPlayer = vm.player != null;
      // Overlap: the second call starts before the first can reassign `_player`.
      await Future.wait([
        vm.loadVideo(r'Z:\highlight_creator_missing\b.mp4'),
        vm.loadVideo(r'Z:\highlight_creator_missing\c.mp4'),
      ]);
      container.dispose();
      // Let the fire-and-forget player disposals surface their errors.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }, (e, _) => errors.add(e));

    if (!hadPlayer) {
      // media_kit native player unavailable (libmpv not on PATH) — the
      // disposal race cannot be exercised here.
      print('media_kit Player unavailable — skipping');
      return;
    }
    expect(
      errors.where((e) => e.toString().contains('has been disposed')),
      isEmpty,
      reason: 'loadVideo must not dispose the same Player twice',
    );
  }, timeout: const Timeout(Duration(seconds: 30)));
}
