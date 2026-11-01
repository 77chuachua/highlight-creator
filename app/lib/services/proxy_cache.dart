import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/services/error_logger.dart';

/// Where a source is in the proxy pipeline.
enum ProxyState { queued, working, ready, failed }

/// State of one proxy file, also mirrored to the `.json` sidecar beside it.
class ProxyEntry {
  const ProxyEntry({
    required this.sourcePath,
    required this.proxyPath,
    required this.state,
    required this.progress,
    required this.sizeBytes,
    required this.updatedAt,
    this.error,
  });

  final String sourcePath;
  final String proxyPath;
  final ProxyState state;

  /// 0–100, only meaningful while [state] is [ProxyState.queued] or working.
  final int progress;
  final String? error;
  final int sizeBytes;
  final DateTime updatedAt;

  ProxyEntry copyWith({
    ProxyState? state,
    int? progress,
    String? error,
    bool clearError = false,
    int? sizeBytes,
  }) {
    return ProxyEntry(
      sourcePath: sourcePath,
      proxyPath: proxyPath,
      state: state ?? this.state,
      progress: progress ?? this.progress,
      error: clearError ? null : (error ?? this.error),
      sizeBytes: sizeBytes ?? this.sizeBytes,
      updatedAt: DateTime.now(),
    );
  }

  Map<String, Object?> toJson() => {
        'sourcePath': sourcePath,
        'proxyPath': proxyPath,
        'state': state.name,
        'progress': progress,
        'error': error,
        'sizeBytes': sizeBytes,
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Null when the sidecar is unreadable or written by a newer version.
  static ProxyEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final sourcePath = json['sourcePath'];
    final proxyPath = json['proxyPath'];
    if (sourcePath is! String || proxyPath is! String) return null;
    ProxyState? state;
    for (final value in ProxyState.values) {
      if (value.name == json['state']) {
        state = value;
        break;
      }
    }
    if (state == null) return null;
    return ProxyEntry(
      sourcePath: sourcePath,
      proxyPath: proxyPath,
      state: state,
      progress: (json['progress'] as num?)?.toInt().clamp(0, 100) ?? 0,
      error: json['error'] as String?,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

/// Background 720p proxy transcode for the phone-marking page.
///
/// One ffmpeg at a time (docs/phone_marking.md): the phone plays the proxy, and
/// the proxy keeps the source timeline byte-for-byte, so a mark made on the
/// phone needs no time mapping on the desktop. Files live under
/// `%USERPROFILE%\HighlightCreator\temp\proxy`, which the existing Cache files
/// dialog already clears.
class ProxyCache {
  ProxyCache({Future<String?> Function()? findFfmpeg})
      : _findFfmpeg = findFfmpeg ?? VideoProcessingService.findFfmpeg;

  /// Resolves ffmpeg; injected by tests so nothing has to be installed.
  final Future<String?> Function() _findFfmpeg;

  final Map<String, ProxyEntry> _entries = {};
  final List<_Job> _queue = [];

  /// Every ffmpeg this class started, so app exit can kill them (see
  /// [shutdownAll]); `exit(0)` gives no chance to await anything.
  static final Set<Process> _running = <Process>{};

  Process? _process;

  /// Source path being transcoded right now, so a poll cannot queue it twice.
  String? _active;
  bool _draining = false;
  bool _shutdown = false;
  DateTime _lastSidecarWrite = DateTime.fromMillisecondsSinceEpoch(0);

  /// `%USERPROFILE%\HighlightCreator\temp\proxy`.
  static String get dir => '${AppPaths.tempDir}${Platform.pathSeparator}proxy';

  /// `<dir>\<sha1(source path)>.mp4`.
  static String pathFor(String sourcePath) =>
      '${dir}${Platform.pathSeparator}${sha1.convert(utf8.encode(sourcePath))}.mp4';

  /// `<proxy without .mp4>.json`.
  static String sidecarFor(String proxyPath) =>
      '${proxyPath.substring(0, proxyPath.length - 4)}.json';

  /// Current state of [sourcePath]'s proxy, loaded from its sidecar on first
  /// use. A `ready` sidecar whose mp4 is gone (Cache files dialog cleared it)
  /// reads as `queued` so the next [ensureQueued] regenerates it.
  ProxyEntry entryFor(String sourcePath) {
    final cached = _entries[sourcePath];
    if (cached != null) return cached;

    final proxyPath = pathFor(sourcePath);
    final stored = _readSidecar(proxyPath);
    // Paths are rebuilt from the source, never taken from the sidecar: the
    // file on disk is user-writable and must not decide what gets served.
    var entry = ProxyEntry(
      sourcePath: sourcePath,
      proxyPath: proxyPath,
      state: stored?.state ?? ProxyState.queued,
      progress: stored?.progress ?? 0,
      error: stored?.error,
      sizeBytes: stored?.sizeBytes ?? 0,
      updatedAt: stored?.updatedAt ?? DateTime.now(),
    );
    if (entry.state == ProxyState.ready && !File(proxyPath).existsSync()) {
      entry = entry.copyWith(state: ProxyState.queued, progress: 0);
    }
    return _entries[sourcePath] = entry;
  }

  /// Queue a transcode unless the proxy is already there or in flight.
  ///
  /// A `working` sidecar from a previous run is queued again: the process that
  /// wrote it is gone, and its `.tmp.mp4` is worth nothing.
  ///
  /// [durationMs] comes from the project's source row, so progress needs no
  /// ffprobe round trip.
  void ensureQueued(String sourcePath, {int durationMs = 0}) {
    if (_shutdown) return;
    final entry = entryFor(sourcePath);
    if (entry.state == ProxyState.ready) return;
    if (_active == sourcePath) return;
    if (_queue.any((job) => job.sourcePath == sourcePath)) return;
    _queue.add(_Job(sourcePath, entry.proxyPath, durationMs));
    _publish(
      entry.copyWith(state: ProxyState.queued, progress: 0, clearError: true),
      force: true,
    );
    unawaited(_drain());
  }

  /// The proxy file to serve, or null while it is not ready.
  ///
  /// The path is derived from [sourcePath] here, never taken from a sidecar or
  /// a request: the sidecar is on disk where anything could have edited it.
  String? readyPath(String sourcePath) {
    if (entryFor(sourcePath).state != ProxyState.ready) return null;
    final path = pathFor(sourcePath);
    return File(path).existsSync() ? path : null;
  }

  /// Drop the queue and kill the ffmpeg in flight; used when the server stops.
  Future<void> shutdown() async {
    _shutdown = true;
    _queue.clear();
    final process = _process;
    _process = null;
    if (process != null) _kill(process);
  }

  /// Accept work again after [shutdown] (the server was restarted).
  void resume() {
    _shutdown = false;
  }

  /// Kill every ffmpeg this class started, synchronously, for app exit.
  static void shutdownAll() {
    for (final process in _running.toList()) {
      _kill(process);
    }
    _running.clear();
  }

  static void _kill(Process process) {
    try {
      process.kill();
    } catch (_) {
      // Already gone.
    }
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty && !_shutdown) {
        await _run(_queue.removeAt(0));
      }
    } finally {
      _draining = false;
    }
  }

  /// Transcode one source: `<proxy>.tmp.mp4` first, renamed on success so a
  /// half-written file can never look playable.
  Future<void> _run(_Job job) async {
    _active = job.sourcePath;
    _publish(
      ProxyEntry(
        sourcePath: job.sourcePath,
        proxyPath: job.proxyPath,
        state: ProxyState.working,
        progress: 0,
        sizeBytes: 0,
        updatedAt: DateTime.now(),
      ),
      force: true,
    );

    Process? process;
    try {
      final ffmpeg = await _findFfmpeg();
      if (ffmpeg == null) {
        _fail(job, 'ffmpeg.exe not found');
        return;
      }
      Directory(File(job.proxyPath).parent.path).createSync(recursive: true);
      final tmp = '${job.proxyPath}.tmp.mp4';
      process = await Process.start(ffmpeg, [
        '-y',
        // `-progress pipe:1` is the only machine-readable progress ffmpeg has;
        // `-nostats` keeps stderr to real diagnostics.
        '-progress', 'pipe:1',
        '-nostats',
        '-i', job.sourcePath,
        // Resolution only: no trim, no fps change, no audio shift, so proxy
        // time == source time (docs/phone_marking.md).
        '-vf', 'scale=-2:720',
        '-c:v', 'libx264',
        '-preset', 'veryfast',
        '-crf', '28',
        '-c:a', 'aac',
        '-movflags', '+faststart',
        tmp,
      ]);
      _process = process;
      _running.add(process);

      final stderrTail = _Tail(4000);
      process.stderr.transform(utf8.decoder).listen(stderrTail.add);

      // `out_time_ms` and `out_time_us` are both microseconds (FFmpeg 7 emits
      // out_time_us); the same parsing the render pipeline uses.
      final outTime = RegExp(r'out_time_(?:us|ms)=(-?\d+)');
      final durationSecs = job.durationMs / 1000.0;
      var buffer = '';
      final stdoutDone = Completer<void>();
      process.stdout.transform(utf8.decoder).listen(
        (chunk) {
          buffer += chunk;
          var newline = buffer.indexOf('\n');
          while (newline >= 0) {
            final line = buffer.substring(0, newline);
            buffer = buffer.substring(newline + 1);
            final match = outTime.firstMatch(line);
            if (match != null && durationSecs > 0) {
              final seconds = int.parse(match.group(1)!) / 1000000.0;
              final percent = (seconds / durationSecs * 100).clamp(0, 100);
              _progress(job, percent.round());
            }
            newline = buffer.indexOf('\n');
          }
        },
        onDone: () => stdoutDone.complete(),
      );

      final exitCode = await process.exitCode;
      await stdoutDone.future;
      _process = null;
      _running.remove(process);
      if (_shutdown) return;
      if (exitCode != 0) {
        _fail(job, stderrTail.toString().trim());
        return;
      }

      final dest = File(job.proxyPath);
      if (dest.existsSync()) dest.deleteSync();
      File(tmp).renameSync(job.proxyPath);
      _publish(
        ProxyEntry(
          sourcePath: job.sourcePath,
          proxyPath: job.proxyPath,
          state: ProxyState.ready,
          progress: 100,
          sizeBytes: dest.lengthSync(),
          updatedAt: DateTime.now(),
        ),
        force: true,
      );
    } catch (e, st) {
      ErrorLogger.log(e, st, source: 'phone-marking-proxy');
      if (!_shutdown) _fail(job, '$e');
    } finally {
      if (process != null) {
        _running.remove(process);
        if (identical(_process, process)) _process = null;
      }
      if (_active == job.sourcePath) _active = null;
    }
  }

  void _progress(_Job job, int percent) {
    final entry = _entries[job.sourcePath];
    if (entry == null || entry.state == ProxyState.ready) return;
    if (entry.progress == percent) return;
    // ponytail: one sidecar write per second, not per progress tick; the state
    // changes (queued/working/ready/failed) always write. Losing a few percent
    // to a crash only matters if the user watches the sidecar.
    _publish(entry.copyWith(state: ProxyState.working, progress: percent));
  }

  void _fail(_Job job, String error) {
    try {
      final tmp = File('${job.proxyPath}.tmp.mp4');
      if (tmp.existsSync()) tmp.deleteSync();
    } catch (_) {
      // Locked; the temp folder is clearable from the Cache files dialog.
    }
    _publish(
      ProxyEntry(
        sourcePath: job.sourcePath,
        proxyPath: job.proxyPath,
        state: ProxyState.failed,
        progress: 0,
        error: error.isEmpty ? 'ffmpeg failed' : error,
        sizeBytes: 0,
        updatedAt: DateTime.now(),
      ),
      force: true,
    );
  }

  void _publish(ProxyEntry entry, {bool force = false}) {
    _entries[entry.sourcePath] = entry;
    final now = DateTime.now();
    if (!force && now.difference(_lastSidecarWrite) < const Duration(seconds: 1)) {
      return;
    }
    _lastSidecarWrite = now;
    try {
      final file = File(sidecarFor(entry.proxyPath));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode(entry.toJson()));
    } catch (e, st) {
      ErrorLogger.log(e, st, source: 'phone-marking-proxy');
    }
  }

  ProxyEntry? _readSidecar(String proxyPath) {
    try {
      final file = File(sidecarFor(proxyPath));
      if (!file.existsSync()) return null;
      return ProxyEntry.fromJson(jsonDecode(file.readAsStringSync()));
    } catch (e, st) {
      ErrorLogger.log(e, st, source: 'phone-marking-proxy');
      return null;
    }
  }
}

class _Job {
  const _Job(this.sourcePath, this.proxyPath, this.durationMs);

  final String sourcePath;
  final String proxyPath;
  final int durationMs;
}

/// Keeps the last [limit] characters written to it: ffmpeg's failure is at the
/// end of stderr, and the beginning is just the input probe.
class _Tail {
  _Tail(this.limit);

  final int limit;
  final StringBuffer _buffer = StringBuffer();

  void add(String chunk) {
    _buffer.write(chunk);
    if (_buffer.length > limit * 2) {
      final text = _buffer.toString();
      _buffer
        ..clear()
        ..write(text.substring(text.length - limit));
    }
  }

  @override
  String toString() {
    final text = _buffer.toString();
    return text.length <= limit ? text : text.substring(text.length - limit);
  }
}
