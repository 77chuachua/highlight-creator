import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:highlight_creator/data/app_paths.dart';

/// Minimal persistent key-value store backed by a JSON file.
class SettingsService {
  /// [path] defaults to the shared user settings file; tests inject a temp
  /// path so they don't touch the real profile.
  SettingsService({String? path}) : _path = path ?? AppPaths.settingsPath;

  final String _path;
  Map<String, dynamic> _data = {};
  bool _loaded = false;
  Future<void>? _loading;

  /// Concurrent callers share one in-flight load. A read that starts while
  /// the file is still being read must await the same load instead of
  /// seeing empty data and falling back to defaults.
  Future<void> _ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final file = File(_path);
      // ponytail: the async exists() is deliberate — existsSync() closes its
      // handle on an IO worker thread and can race an immediate deleteSync()
      // on Windows (guide_dialog_test teardown, errno 32).
      // ignore: avoid_slow_async_io
      if (await file.exists()) {
        _data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      }
    } catch (_) {
      _data = {};
    } finally {
      _loaded = true;
      _loading = null;
    }
  }

  Future<String> get language async {
    await _ensureLoaded();
    return (_data['language'] as String?) ?? 'English';
  }

  Future<void> setLanguage(String value) async {
    await _ensureLoaded();
    _data['language'] = value;
    await _save();
  }

  Future<String> get themeMode async {
    await _ensureLoaded();
    return (_data['themeMode'] as String?) ?? 'dark';
  }

  Future<void> setThemeMode(String value) async {
    await _ensureLoaded();
    _data['themeMode'] = value;
    await _save();
  }

  /// Whether the beginner guide dialog pops up automatically on startup.
  Future<bool> get guideAutoShow async {
    await _ensureLoaded();
    return _data['guideAutoShow'] as bool? ?? true;
  }

  Future<void> setGuideAutoShow(bool value) async {
    await _ensureLoaded();
    _data['guideAutoShow'] = value;
    await _save();
  }

  /// Last base time entered in the Go-to dialog (as 'hh:mm:ss'), if any.
  Future<String?> get gotoBaseTime async {
    await _ensureLoaded();
    return _data['gotoBaseTime'] as String?;
  }

  Future<void> setGotoBaseTime(String value) async {
    await _ensureLoaded();
    _data['gotoBaseTime'] = value;
    await _save();
  }

  Future<void> _save() async {
    try {
      final file = File(_path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_data));
    } catch (_) {}
  }
}

final settingsServiceProvider = Provider<SettingsService>((ref) => SettingsService());
