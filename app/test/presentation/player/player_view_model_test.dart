import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/presentation/player/player_state.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';

void main() {
  group('VideoPlayerViewModel', () {
    late ProviderContainer container;
    late VideoPlayerViewModel vm;

    setUp(() {
      container = ProviderContainer();
      vm = container.read(videoPlayerProvider.notifier);
      addTearDown(container.dispose);
    });

    VideoPlayerState readState() =>
        container.read(videoPlayerProvider);

    test('initial state is idle', () {
      final s = readState();
      expect(s.status, PlayerStatus.idle);
      expect(s.hasVideo, false);
    });

    test('loadVideo with empty path sets error', () async {
      await vm.loadVideo('');
      final s = readState();
      expect(s.status, PlayerStatus.error);
      expect(s.errorMessage, 'Empty path');
    });

    test('loadVideo with non-existent file sets error', () async {
      await vm.loadVideo('/nonexistent/video.mp4');
      final s = readState();
      // Should be in error state since file doesn't exist.
      expect(s.status, PlayerStatus.error);
    });

    test('stop resets to idle', () async {
      await vm.stop();
      final s = readState();
      expect(s.status, PlayerStatus.idle);
    });

    test('play with no video is a no-op', () async {
      await vm.play();
      expect(readState().status, PlayerStatus.idle);
    });

    test('live position notifier is decoupled from provider state', () async {
      // The tracker playhead is fed from positionNotifier — NOT provider
      // state — so continuous playback ticks never rebuild the whole UI
      // (4K lag regression vs `first real release`, issues.md).
      vm.positionNotifier.value = const Duration(seconds: 70);
      await Future<void>.delayed(Duration.zero);
      expect(readState().position, Duration.zero,
          reason: 'live position must stay off provider state');
    });
  });

  group('VideoPlayerState', () {
    test('positionFormatted returns mm:ss', () {
      const s = VideoPlayerState(
        position: Duration(minutes: 1, seconds: 30),
        duration: Duration(minutes: 2, seconds: 30),
      );
      expect(s.positionFormatted, '01:30');
      expect(s.durationFormatted, '02:30');
    });

    test('sliderValue returns fraction', () {
      const s = VideoPlayerState(
        position: Duration(minutes: 1, seconds: 15),
        duration: Duration(minutes: 2, seconds: 30),
      );
      expect(s.sliderValue, 0.5);
    });
  });
}
