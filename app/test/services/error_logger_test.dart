import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/services/error_logger.dart';

void main() {
  test('ErrorLogger appends errors to a daily log file under baseDir/logs',
      () {
    final tmp = Directory.systemTemp.createTempSync('hlc_error_log_test');
    AppPaths.overrideBaseDir = tmp.path;
    addTearDown(() {
      AppPaths.overrideBaseDir = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    ErrorLogger.log(StateError('boom'), StackTrace.current, source: 'test');

    final logDir = Directory('${tmp.path}${Platform.pathSeparator}logs');
    expect(logDir.existsSync(), isTrue);
    final files = logDir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final content = files.single.readAsStringSync();
    expect(content.contains('[test]'), isTrue);
    expect(content.contains('boom'), isTrue);
  });
}
