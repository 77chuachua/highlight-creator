import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/presentation/player/player_state.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';

/// A project re-opened from a moved folder still names its old video paths.
/// mpv never starts on a missing file, so the player used to sit on the loading
/// spinner forever; loadVideo must report the dead path instead.
void main() {
  test('loadVideo on a missing file fails fast with the path, not a hang',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final vm = container.read(videoPlayerProvider.notifier);
    await vm.loadVideo(r'C:\no\such\folder\clip.mp4');

    final state = container.read(videoPlayerProvider);
    expect(state.status, PlayerStatus.error);
    expect(state.hasError, isTrue);
    expect(state.errorMessage, contains('video not found'));
    expect(state.errorMessage, contains(r'C:\no\such\folder\clip.mp4'));
    // No Player is created for a dead path, so nothing is left playing.
    expect(vm.player, isNull);
    expect(vm.videoController, isNull);
  });

  test('an empty path is rejected without touching the player', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(videoPlayerProvider.notifier).loadVideo('');

    final state = container.read(videoPlayerProvider);
    expect(state.status, PlayerStatus.error);
    expect(container.read(videoPlayerProvider.notifier).player, isNull);
  });
}
