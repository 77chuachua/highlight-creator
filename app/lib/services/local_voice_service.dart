import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/services/error_logger.dart';

/// What the local engine said about one request.
class LocalVoiceResult {
  final String? path;
  final String? error;

  const LocalVoiceResult.ok(this.path) : error = null;
  const LocalVoiceResult.failed(this.error) : path = null;

  bool get ok => path != null;
}

/// Speaks any text with the user's own voice, on this machine.
///
/// The engine is a Python worker (see tools/voice_clone) that keeps the
/// cloning model warm; the app talks to it over stdin/stdout with JSON
/// lines, the same way it drives ffmpeg. Nothing leaves the machine: the
/// model is cached locally and the reference recording stays on disk.
class LocalVoiceService {
  static Process? _worker;
  static Completer<Map<String, dynamic>>? _pending;
  static Future<Process?>? _starting;
  static String _lastError = '';

  /// Where the engine lives (setup.bat puts it there).
  static String get dir => AppPaths.voiceCloneDir;

  /// The plugin description written by `setup.py`.
  ///
  /// The app reads paths from here instead of hard-coding them, so a different
  /// engine (a newer CosyVoice, a cloud backend) only has to ship a manifest.
  static Map<String, dynamic>? get manifest {
    final file = File('$dir${Platform.pathSeparator}plugin.json');
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  /// A manifest entry resolved against [dir], or null when it is missing.
  static String? _fromManifest(String key) {
    final value = manifest?[key];
    if (value is! String || value.isEmpty) return null;
    return '$dir${Platform.pathSeparator}$value';
  }

  /// What the manifest calls this engine ("cosyvoice2").
  static String get engineName => (manifest?['engine'] as String?) ?? '';

  static String get pythonPath =>
      _fromManifest('python') ??
      '$dir${Platform.pathSeparator}venv'
          '${Platform.pathSeparator}Scripts${Platform.pathSeparator}python.exe';

  static String get workerPath =>
      _fromManifest('worker') ?? '$dir${Platform.pathSeparator}worker.py';

  /// The CosyVoice checkout the worker imports.
  static String get repoPath =>
      _fromManifest('repo') ?? '$dir${Platform.pathSeparator}CosyVoice';

  /// The cloned model.
  static String get modelPath =>
      _fromManifest('model') ??
      '$dir${Platform.pathSeparator}models${Platform.pathSeparator}CosyVoice2-0.5B';

  /// The program that creates voice packs, when the plugin ships one.
  static String? get studioPath => _fromManifest('studio');

  /// Whether the studio exists; without it the app can still synthesise with
  /// packs that were imported from elsewhere.
  static bool get hasStudio {
    final path = studioPath;
    return path != null && File(path).existsSync();
  }

  /// The model file every engine writes; used to decide "installed".
  static String get _modelMarker =>
      '$modelPath${Platform.pathSeparator}cosyvoice2.yaml';

  /// Whether the engine is installed.
  static bool get isInstalled =>
      File(pythonPath).existsSync() &&
      File(workerPath).existsSync() &&
      File(_modelMarker).existsSync();

  /// The message shown when the engine is missing.
  static String get installHint =>
      '本地克隆引擎未安装,请先运行 tools\\voice_clone\\setup.bat';

  /// The last error the engine reported.
  static String get lastError => _lastError;

  /// Records the reason and returns it as the result.
  static LocalVoiceResult _fail(String reason) {
    ErrorLogger.log(reason, null, source: 'voice-clone');
    return LocalVoiceResult.failed(reason);
  }

  /// Speaks [text] in the voice of the [reference] recording and writes it to
  /// [output]. [promptText] is what the reference recording says - the model
  /// needs it to line the text up with the sample.
  /// Speaks [text] in the recorded voice.
  ///
  /// [prosodyReference] is an optional clip whose intonation the engine copies:
  /// it renders the sentence with that clip's delivery first (cross-lingual
  /// zero-shot), then swaps the timbre for [reference] with a voice
  /// conversion. Without it the plain zero-shot path runs.
  static Future<LocalVoiceResult> speak({
    required String text,
    required String promptText,
    required String reference,
    required String output,
    String? prosodyReference,
    double speed = 1,
    String? instruct,
  }) async {
    // Every exit records why: the dialog used to swallow the reason, and the
    // hidden snackbar was the only place the user could have read it.
    if (!isInstalled) return _fail(installHint);
    if (!File(reference).existsSync()) {
      return _fail('找不到参考录音:$reference');
    }
    final worker = await _ensureWorker();
    if (worker == null) {
      return _fail(
          _lastError.isEmpty ? '克隆引擎启动失败' : _lastError);
    }
    final request = jsonEncode({
      'text': text,
      'prompt_text': promptText,
      'reference': reference,
      'output': output,
      if (prosodyReference != null && prosodyReference.isNotEmpty)
        'prosody_reference': prosodyReference,
      if (speed != 1) 'speed': speed,
      if (instruct != null && instruct.trim().isNotEmpty)
        'instruct': instruct.trim(),
    });
    final reply = Completer<Map<String, dynamic>>();
    _pending = reply;
    try {
      // stdin defaults to the ANSI code page on Windows and the worker decodes
      // UTF-8, so writing "老庄这脚球" through the default turned it into lone
      // surrogates and the tokenizer died on a TextEncodeInput TypeError.
      worker.stdin.encoding = utf8;
      worker.stdin.writeln(request);
      await worker.stdin.flush();
    } catch (e) {
      _pending = null;
      ErrorLogger.log(e, null, source: 'voice-clone');
      return LocalVoiceResult.failed('克隆引擎没有响应:$e');
    }
    Map<String, dynamic> answer;
    try {
      answer = await reply.future.timeout(const Duration(minutes: 10));
    } on TimeoutException {
      _pending = null;
      await _stopWorker();
      ErrorLogger.log('克隆超时: $text', null, source: 'voice-clone');
      return LocalVoiceResult.failed('克隆超时,请重试或换短一点的解说');
    }
    if (answer['ok'] == true) {
      return LocalVoiceResult.ok((answer['path'] as String?) ?? output);
    }
    final reason = (answer['error'] as String?) ?? '克隆失败';
    ErrorLogger.log('克隆失败: $reason (文本: $text)', null,
        source: 'voice-clone');
    return LocalVoiceResult.failed(reason);
  }

  /// Starts the worker if it is not running yet.
  static Future<Process?> _ensureWorker() async {
    final running = _worker;
    if (running != null) return running;
    final starting = _starting;
    if (starting != null) return starting;
    final future = _startWorker();
    _starting = future;
    try {
      return await future;
    } finally {
      _starting = null;
    }
  }

  static Future<Process?> _startWorker() async {
    try {
      final process = await Process.start(
        pythonPath,
        [workerPath],
        environment: {
          // The model comes from the mirror; the direct host is unreachable.
          'HF_ENDPOINT': 'https://hf-mirror.com',
          'HF_HOME': '$dir${Platform.pathSeparator}models',
          'HIGHLIGHT_COSYVOICE_ROOT': repoPath,
          'HIGHLIGHT_COSYVOICE_MODEL': modelPath,
          'PYTHONIOENCODING': 'utf-8',
        },
        includeParentEnvironment: true,
      );
      _worker = process;
      process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(_onReply);
      process.stderr.transform(utf8.decoder).listen((line) {
        if (line.trim().isEmpty) return;
        _lastError = line.trim();
        debugPrint('[voice-clone] $line');
      });
      unawaited(process.exitCode.then((code) {
        _worker = null;
        final pending = _pending;
        _pending = null;
        if (pending != null && !pending.isCompleted) {
          pending.completeError(StateError('克隆引擎已退出(code $code)'));
        }
      }));
      return process;
    } catch (e) {
      _lastError = '$e';
      return null;
    }
  }

  static void _onReply(String line) {
    final text = line.trim();
    // CosyVoice and modelscope print progress on the same stream (the worker
    // now diverts them, but a stray line must never fail the request).
    if (!text.startsWith('{')) return;
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic> && decoded.containsKey('ok')) {
        payload = decoded;
      }
    } catch (_) {
      // Not our protocol line.
    }
    if (payload == null) return;
    final pending = _pending;
    if (pending == null || pending.isCompleted) return;
    _pending = null;
    pending.complete(payload);
  }

  /// Stops the worker; the model is reloaded on the next request.
  static Future<void> _stopWorker() async {
    final worker = _worker;
    _worker = null;
    if (worker == null) return;
    try {
      worker.kill();
    } catch (_) {}
  }

  /// Release the model when the app closes.
  ///
  /// The worker is a real child process; without this it outlives the app and
  /// keeps ~4 GB of VRAM allocated until the machine reboots.
  static Future<void> shutdown() => _stopWorker();
}
