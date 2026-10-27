import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/player_state.dart';
import 'package:highlight_creator/presentation/player/record_view_model.dart';
import 'package:highlight_creator/services/error_logger.dart';

/// The file path of the source that follows [currentPath] in [sources], or
/// null when the current file is not a project source or is the last one.
/// Matching falls back to the file name so paths loaded from different
/// locations (e.g. temp copies) still chain (issues.md: keep playing through
/// the whole source list).
String? nextSourcePath(List<VideoSource> sources, String currentPath) {
  if (sources.isEmpty || currentPath.isEmpty) return null;
  final currentBase = currentPath.split(RegExp(r'[\\/]')).last;
  final idx = sources.indexWhere((s) =>
      s.filePath == currentPath ||
      s.filePath.split(RegExp(r'[\\/]')).last == currentBase);
  if (idx < 0 || idx >= sources.length - 1) return null;
  return sources[idx + 1].filePath;
}

/// Manages video playback using media_kit's Player.
class VideoPlayerViewModel extends Notifier<VideoPlayerState> {
  Player? _player;
  VideoController? _videoController;
  StreamSubscription? _sub;
  StreamSubscription? _posSub;
  StreamSubscription? _cplSub;
  bool _advancing = false;

  /// Monotonic token: only the newest [loadVideo]/[stop] may own the shared
  /// [Player] and subscriptions. Two autoplay listeners (this view-model's
  /// `completed` listener and `SourceFileList._advanceToNext`) can call
  /// [loadVideo] at the same time; without this they both disposed the same
  /// live Player and the second dispose threw
  /// `Assertion failed: "[Player] has been disposed"` (issues.md).
  int _loadSeq = 0;

  final Stopwatch _posClock = Stopwatch()..start();

  /// Live playback position for the tracker playhead ONLY. Kept off the
  /// [videoPlayerProvider] state so that continuous position ticks never
  /// rebuild the player UI (that caused 4K playback to lag — regression
  /// vs `first real release`, where playback never touched provider state).
  final ValueNotifier<Duration> positionNotifier = ValueNotifier(Duration.zero);

  Player? get player => _player;
  VideoController? get videoController => _videoController;

  @override
  VideoPlayerState build() {
    ref.onDispose(_cleanup);
    return const VideoPlayerState();
  }

  Future<void> loadVideo(String path, {Duration? initialPosition}) async {
    if (path.isEmpty) {
      state = state.copyWith(status: PlayerStatus.error, errorMessage: 'Empty path');
      return;
    }

    final seq = ++_loadSeq;

    // Detach the old player synchronously (before the first await) so a racing
    // loadVideo can never dispose the same instance again.
    final previous = _player;
    _player = null;
    _videoController = null;
    await previous?.dispose();
    if (seq != _loadSeq) return;

    await _sub?.cancel();
    await _posSub?.cancel();
    await _cplSub?.cancel();
    _sub = null;
    _posSub = null;
    _cplSub = null;
    if (seq != _loadSeq) return;

    state = state.copyWith(status: PlayerStatus.loading, videoPath: path, clearError: true);

    // A project opened from an old location still names the videos it was
    // built from, and those paths are dead. mpv does not fail fast on a
    // missing file — the playlist simply never starts — which used to leave the
    // player on the loading spinner forever with no way out. Catch it here,
    // before any Player is created, so the user gets the path in the error.
    if (!File(path).existsSync()) {
      ErrorLogger.log('video not found: $path', null, source: 'player');
      state = state.copyWith(
        status: PlayerStatus.error,
        errorMessage: '视频文件不存在 / video not found:\n$path',
      );
      return;
    }

    try {
      final player = Player();
      _player = player;
      _videoController = VideoController(player);

      // Media.start sets mpv's `start` property so a freshly opened video
      // resumes at the exact position instead of the head (the same trick the
      // auto-gen dialog uses for global-timeline seeks).
      final openClock = Stopwatch()..start();
      await player.open(Media(path, start: initialPosition))
          .timeout(const Duration(seconds: 20));
      ErrorLogger.log('opened in ${openClock.elapsedMilliseconds}ms: $path', null,
          source: 'player');

      // Superseded while opening: drop our player without touching the state
      // the newer load already owns.
      if (seq != _loadSeq) {
        if (identical(_player, player)) {
          _player = null;
          _videoController = null;
        }
        await player.dispose();
        return;
      }

      _sub = player.stream.playlist.listen((_) {
        _syncState();
      });

      // Live playback position → the tracker notifier (throttled to ~15Hz.
      // This deliberately does NOT write to provider state).
      _posSub = player.stream.position.listen((p) {
        if (_posClock.elapsedMilliseconds < 66) return;
        _posClock.reset();
        positionNotifier.value = p;
      });

      // Chained playback (issues.md): when a source video ends, keep playing
      // the next source in the list until the last file.
      _cplSub = player.stream.completed.listen((done) {
        if (done) _advanceToNextSource();
      });

      _syncState();
      // A playlist that reports neither playing nor paused would leave the
      // spinner on top of a video that is already running.
      if (seq == _loadSeq && state.status == PlayerStatus.loading) {
        state = state.copyWith(status: PlayerStatus.paused);
      }
    } catch (e, st) {
      ErrorLogger.log(e, st, source: 'player');
      if (seq == _loadSeq) {
        state = state.copyWith(
            status: PlayerStatus.error, errorMessage: 'Failed: $e');
      }
    }
  }

  /// Advance to the next project source when the current one finishes
  /// playing. No-op for the last source or for files that are not sources
  /// (e.g. the rendered highlight video).
  Future<void> _advanceToNextSource() async {
    if (_advancing) return;
    final current = state.videoPath;
    if (current == null || current.isEmpty) return;
    final sources =
        ref.read(recordProvider).selectedProject?.sources ?? const <VideoSource>[];
    final next = nextSourcePath(sources, current);
    if (next == null) return;
    _advancing = true;
    try {
      await loadVideo(next);
      await play();
    } finally {
      _advancing = false;
    }
  }

  void _syncState() {
    if (_player == null) return;
    final s = _player!.state;
    final newStatus = s.playing ? PlayerStatus.playing : PlayerStatus.paused;
    final newSpeed = s.rate;

    if (state.position != s.position ||
        state.duration != s.duration ||
        state.status != newStatus ||
        state.playbackSpeed != newSpeed) {
      state = state.copyWith(
        position: s.position,
        duration: s.duration,
        status: newStatus,
        playbackSpeed: newSpeed,
      );
    }
  }

  Future<void> play() async {
    if (!state.hasVideo) return;
    await _player?.play();
    // Update state immediately for responsive UI.
    state = state.copyWith(status: PlayerStatus.playing);
  }

  Future<void> pause() async {
    await _player?.pause();
    // Update state immediately for responsive UI.
    state = state.copyWith(status: PlayerStatus.paused);
  }

  Future<void> togglePlayPause() async {
    if (state.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }

  Future<void> seek(Duration pos) async {
    if (!state.hasVideo) return;
    await _player?.seek(pos);
    // Reflect the seek immediately (only user-initiated, low frequency).
    positionNotifier.value = pos;
    _syncState();
  }

  Future<void> seekRelative(Duration delta) async {
    if (_player == null) return;
    await seek(_player!.state.position + delta);
  }

  Future<void> seekToSlider(double v) async {
    if (!state.hasVideo) return;
    final dur = _player?.state.duration ?? state.duration;
    await seek(Duration(milliseconds: (v * dur.inMilliseconds).round()));
  }

  Future<void> setSpeed(double speed) async {
    await _player?.setRate(speed.clamp(0.25, 4.0));
    state = state.copyWith(playbackSpeed: speed.clamp(0.25, 4.0));
  }

  Future<void> cycleSpeed() async {
    const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 4.0];
    final i = (speeds.indexOf(state.playbackSpeed) + 1) % speeds.length;
    await setSpeed(speeds[i]);
  }

  Future<void> stop() async {
    _loadSeq++; // invalidate any in-flight loadVideo
    final player = _player;
    _player = null;
    _videoController = null;
    await _sub?.cancel();
    _sub = null;
    await _posSub?.cancel();
    _posSub = null;
    await _cplSub?.cancel();
    _cplSub = null;
    await player?.dispose();
    state = const VideoPlayerState();
  }

  void _cleanup() {
    _loadSeq++;
    _sub?.cancel();
    _posSub?.cancel();
    _cplSub?.cancel();
    final player = _player;
    _player = null;
    _videoController = null;
    player?.dispose();
  }
}

final videoPlayerProvider = NotifierProvider<VideoPlayerViewModel, VideoPlayerState>(
  VideoPlayerViewModel.new,
);