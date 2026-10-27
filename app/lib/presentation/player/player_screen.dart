import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/presentation/player/player_state.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';

/// Full video player screen with video surface overlay and control bar.
class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final FocusNode _focusNode;
  bool _showControls = true;
  Timer? _hideControlsTimer;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _resetHideTimer();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _resetHideTimer() {
    _hideControlsTimer?.cancel();
    setState(() => _showControls = true);
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final vm = ref.read(videoPlayerProvider.notifier);
    final logical = event.logicalKey;

    if (logical == LogicalKeyboardKey.space) {
      vm.togglePlayPause();
      _resetHideTimer();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.arrowLeft) {
      vm.seekRelative(const Duration(seconds: -5));
      _resetHideTimer();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.arrowRight) {
      vm.seekRelative(const Duration(seconds: 5));
      _resetHideTimer();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.keyJ) {
      vm.seekRelative(const Duration(seconds: -10));
      _resetHideTimer();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.keyK) {
      vm.togglePlayPause();
      _resetHideTimer();
      return KeyEventResult.handled;
    }
    if (logical == LogicalKeyboardKey.keyL) {
      vm.seekRelative(const Duration(seconds: 10));
      _resetHideTimer();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onTapVideo() {
    final vm = ref.read(videoPlayerProvider.notifier);
    vm.togglePlayPause();
    _resetHideTimer();
  }

  Future<void> _pickVideo() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        final path = result.files.single.path;
        if (path != null) {
          final vm = ref.read(videoPlayerProvider.notifier);
          await vm.loadVideo(path);
        }
      }
    } catch (e) {
      // User cancelled or error — silently ignore.
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(videoPlayerProvider);
    final l10n = ref.watch(l10nProvider);

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: () => _resetHideTimer(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildVideoArea(state, context),
            if (state.hasError) _buildErrorOverlay(state, l10n),
            if (state.status == PlayerStatus.idle) _buildIdleOverlay(l10n),
            if (state.status == PlayerStatus.loading)
              const Center(child: CircularProgressIndicator()),
            if (_showControls &&
                (state.status == PlayerStatus.paused ||
                    state.status == PlayerStatus.playing))
              _buildCenterPlayButton(state),
            if (_showControls && state.hasVideo) _buildControlBar(state),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoArea(VideoPlayerState state, BuildContext context) {
    if (!state.hasVideo) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.movie_outlined, size: 80, color: Colors.white24),
        ),
      );
    }

    final vc = ref.read(videoPlayerProvider.notifier).videoController;
    if (vc != null) {
      return GestureDetector(
        onTap: _onTapVideo,
        // Keyed by controller: loadVideo() builds a new Player + VideoController
        // for every file, and reusing the element left the previous, already
        // disposed texture attached — audio played while the picture stayed
        // black until a resize (maximize/fullscreen) forced a fresh surface.
        child: Video(
          key: ValueKey(vc),
          controller: vc,
          fit: BoxFit.contain,
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (state.status == PlayerStatus.loading)
              const CircularProgressIndicator(color: Colors.white54)
            else
              const Icon(Icons.play_circle_outline, size: 64, color: Colors.white54),
            const SizedBox(height: 12),
            Text(
              state.videoPath!.split('/').last,
              style: const TextStyle(color: Colors.white54, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterPlayButton(VideoPlayerState state) {
    return Center(
      child: GestureDetector(
        onTap: _onTapVideo,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(
            state.isPlaying ? Icons.pause : Icons.play_arrow,
            size: 44,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildIdleOverlay(AppStrings l10n) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.video_library_outlined,
              size: 64, color: Colors.white38),
          const SizedBox(height: 16),
          Text(l10n.noVideoLoaded,
              style: const TextStyle(color: Colors.white54, fontSize: 16)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _pickVideo,
            icon: const Icon(Icons.folder_open),
            label: Text(l10n.openVideo),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorOverlay(VideoPlayerState state, AppStrings l10n) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                state.errorMessage ?? l10n.unknownError,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () {
                  ref.read(videoPlayerProvider.notifier).stop();
                },
                child: Text(l10n.dismiss),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlBar(VideoPlayerState state) {
    final theme = Theme.of(context);
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black87,
              Colors.black54,
              Colors.transparent,
            ],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text(state.positionFormatted,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 6),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 12),
                      activeTrackColor: theme.colorScheme.primary,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: theme.colorScheme.primary,
                    ),
                    child: Slider(
                      value: state.sliderValue,
                      onChanged: (v) {
                        ref.read(videoPlayerProvider.notifier).seekToSlider(v);
                      },
                      onChangeEnd: (_) => _resetHideTimer(),
                    ),
                  ),
                ),
                Text(state.durationFormatted,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ControlButton(
                  onTap: () {
                    ref.read(videoPlayerProvider.notifier).cycleSpeed();
                    _resetHideTimer();
                  },
                  child: Text(
                    '${state.playbackSpeed}x',
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                _ControlButton(
                  icon: Icons.replay_5,
                  onTap: () {
                    ref
                        .read(videoPlayerProvider.notifier)
                        .seekRelative(const Duration(seconds: -5));
                    _resetHideTimer();
                  },
                ),
                _ControlButton(
                  icon: state.isPlaying ? Icons.pause : Icons.play_arrow,
                  size: 36,
                  onTap: () {
                    ref.read(videoPlayerProvider.notifier).togglePlayPause();
                    _resetHideTimer();
                  },
                ),
                _ControlButton(
                  icon: Icons.forward_5,
                  onTap: () {
                    ref
                        .read(videoPlayerProvider.notifier)
                        .seekRelative(const Duration(seconds: 5));
                    _resetHideTimer();
                  },
                ),
                _ControlButton(
                  icon: Icons.stop,
                  onTap: () {
                    ref.read(videoPlayerProvider.notifier).stop();
                    _resetHideTimer();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A tappable control bar button.
class _ControlButton extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final double size;
  final VoidCallback onTap;

  const _ControlButton({
    this.icon,
    this.child,
    this.size = 24,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: child ??
            Icon(icon, size: size, color: Colors.white70),
      ),
    );
  }
}
