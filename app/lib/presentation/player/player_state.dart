/// Represents the playback status of the video player.
enum PlayerStatus {
  /// No video loaded.
  idle,

  /// Video is loading / buffering.
  loading,

  /// Video is playing.
  playing,

  /// Video is paused.
  paused,

  /// An error occurred.
  error,
}

/// Immutable state for the video player ViewModel.
class VideoPlayerState {
  final PlayerStatus status;
  final String? videoPath;
  final Duration position;
  final Duration duration;
  final double playbackSpeed;
  final String? errorMessage;

  const VideoPlayerState({
    this.status = PlayerStatus.idle,
    this.videoPath,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.playbackSpeed = 1.0,
    this.errorMessage,
  });

  bool get isPlaying => status == PlayerStatus.playing;
  bool get hasVideo => videoPath != null && videoPath!.isNotEmpty;
  bool get hasError => status == PlayerStatus.error;

  /// Formatted position string (mm:ss).
  String get positionFormatted => _formatDuration(position);

  /// Formatted duration string (mm:ss).
  String get durationFormatted => _formatDuration(duration);

  /// Slider value from 0.0 to 1.0.
  double get sliderValue =>
      duration.inMilliseconds > 0
          ? position.inMilliseconds / duration.inMilliseconds
          : 0.0;

  static String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  VideoPlayerState copyWith({
    PlayerStatus? status,
    String? videoPath,
    Duration? position,
    Duration? duration,
    double? playbackSpeed,
    String? errorMessage,
    bool clearError = false,
    bool clearVideo = false,
  }) {
    return VideoPlayerState(
      status: status ?? this.status,
      videoPath: clearVideo ? null : (videoPath ?? this.videoPath),
      position: position ?? this.position,
      duration: duration ?? this.duration,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}
