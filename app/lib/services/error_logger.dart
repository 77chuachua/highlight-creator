import 'dart:io';

import 'package:highlight_creator/data/app_paths.dart';

/// Appends uncaught errors to a daily log under
/// `%USERPROFILE%\HighlightCreator\logs` so a freeze or crash leaves a trail
/// even in a release build with no console attached.
class ErrorLogger {
  static File _currentFile() {
    final dir = Directory('${AppPaths.baseDir}${Platform.pathSeparator}logs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return File('${dir.path}${Platform.pathSeparator}'
        'error-${now.year}${two(now.month)}${two(now.day)}.log');
  }

  /// Write one entry. Never throws: logging must not become a crash source.
  static void log(Object error, StackTrace? stack, {String source = 'app'}) {
    try {
      _currentFile().writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] [$source] $error\n'
        '${stack ?? ''}\n\n',
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      // ponytail: swallow — a broken log file must not take the app down.
    }
  }
}
