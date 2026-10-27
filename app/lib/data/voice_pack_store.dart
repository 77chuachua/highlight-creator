import 'dart:io';

import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/domain/entities/voice_pack.dart';
import 'package:highlight_creator/services/error_logger.dart';
import 'package:highlight_creator/services/voice_service.dart';

/// Reads, imports and removes voice packs.
///
/// Everything here is plain file work; the audio conversion and the cloning
/// itself belong to the caller and the plugin. Keeping it dependency-free is
/// what lets the format be tested without ffmpeg or a GPU.
class VoicePackStore {
  const VoicePackStore();

  static String get dir => AppPaths.voicesDir;

  Directory _ensureDir() {
    final d = Directory(dir);
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// Every pack on disk, newest first.
  List<VoicePack> list() {
    final d = Directory(dir);
    if (!d.existsSync()) return const [];
    final packs = <VoicePack>[];
    for (final child in d.listSync()) {
      if (child is! Directory) continue;
      if (!child.path.toLowerCase().endsWith(VoicePack.folderSuffix)) continue;
      try {
        final pack = VoicePack.fromDirectory(child);
        if (pack != null) packs.add(pack);
      } catch (e) {
        ErrorLogger.log(e, null, source: 'voice-pack');
      }
    }
    packs.sort((a, b) {
      final at = a.createdAt, bt = b.createdAt;
      if (at != null && bt != null && at != bt) return bt.compareTo(at);
      return a.name.compareTo(b.name);
    });
    return packs;
  }

  VoicePack? find(String id) {
    for (final pack in list()) {
      if (pack.id == id) return pack;
    }
    return null;
  }

  /// A file-name-safe version of [name]: Windows forbids `\ / : * ? " < > |`.
  static String sanitize(String name) {
    var safe = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (safe.isEmpty) safe = '我的声音';
    if (safe.length > 40) safe = safe.substring(0, 40);
    return safe;
  }

  /// The folder a new pack called [name] should take, without clobbering one
  /// that already exists ("我的声音 (2)").
  String _freeFolder(String name) {
    final safe = sanitize(name);
    var candidate = '$dir${Platform.pathSeparator}$safe${VoicePack.folderSuffix}';
    var n = 2;
    while (Directory(candidate).existsSync()) {
      candidate = '$dir${Platform.pathSeparator}'
          '$safe ($n)${VoicePack.folderSuffix}';
      n++;
    }
    return candidate;
  }

  /// Copy a prepared folder (it must contain `reference.wav`) into the pack
  /// directory. Returns the new pack, or null when the source is unusable.
  ///
  /// [styleSource] is an optional intonation reference to copy alongside.
  Future<VoicePack?> importDirectory(
    String sourceDir, {
    String? name,
    String? styleSource,
    String engine = '',
  }) async {
    final source = Directory(sourceDir);
    if (!source.existsSync()) return null;
    final reference =
        File('${source.path}${Platform.pathSeparator}${VoicePack.referenceName}');
    if (!reference.existsSync()) return null;

    _ensureDir();
    final displayName = sanitize(
        name ?? source.uri.pathSegments.last.replaceAll(VoicePack.folderSuffix, ''));
    final target = Directory(_freeFolder(displayName));
    try {
      target.createSync(recursive: true);
      reference.copySync(
          '${target.path}${Platform.pathSeparator}${VoicePack.referenceName}');
      final style = styleSource != null && File(styleSource).existsSync()
          ? styleSource
          : _styleIn(source);
      if (style != null) {
        File(style).copySync(
            '${target.path}${Platform.pathSeparator}${VoicePack.styleName}');
      }
      final preview =
          File('${source.path}${Platform.pathSeparator}${VoicePack.previewName}');
      if (preview.existsSync()) {
        preview.copySync(
            '${target.path}${Platform.pathSeparator}${VoicePack.previewName}');
      }
      final pack = VoicePack(
        id: target.uri.pathSegments.last.replaceAll(VoicePack.folderSuffix, ''),
        name: displayName,
        dir: target.path,
        referencePath:
            '${target.path}${Platform.pathSeparator}${VoicePack.referenceName}',
        stylePath: style == null
            ? null
            : '${target.path}${Platform.pathSeparator}${VoicePack.styleName}',
        createdAt: DateTime.now(),
        referenceSeconds: _seconds(
            '${target.path}${Platform.pathSeparator}${VoicePack.referenceName}'),
        engine: engine,
      );
      File('${target.path}${Platform.pathSeparator}${VoicePack.manifestName}')
          .writeAsStringSync(pack.manifestJson, flush: true);
      return VoicePack.fromDirectory(target);
    } catch (e) {
      ErrorLogger.log(e, null, source: 'voice-pack');
      return null;
    }
  }

  /// Length of a reference recording, so the picker can show it.
  static double _seconds(String path) {
    final duration = VoiceService.wavDuration(path);
    return duration.inMilliseconds / 1000.0;
  }

  String? _styleIn(Directory source) {
    final file =
        File('${source.path}${Platform.pathSeparator}${VoicePack.styleName}');
    return file.existsSync() ? file.path : null;
  }

  /// Turn the pre-pack recordings into a pack, once.
  ///
  /// Before packs existed the app wrote `voices\my_voice.wav` (and an optional
  /// `style.wav`). Those files still work, so they are copied into a pack
  /// rather than moved: a botched migration then costs nothing.
  VoicePack? migrateLegacy({String engine = ''}) {
    final sep = Platform.pathSeparator;
    final legacyReference = File('$dir${sep}my_voice.wav');
    if (!legacyReference.existsSync()) return null;
    // Already migrated (any pack carrying the same bytes by name)?
    for (final pack in list()) {
      if (pack.name == '我的声音' &&
          File(pack.referencePath).lengthSync() ==
              legacyReference.lengthSync()) {
        return pack;
      }
    }
    _ensureDir();
    final target = Directory(_freeFolder('我的声音'));
    try {
      target.createSync(recursive: true);
      legacyReference.copySync(
          '${target.path}${sep}${VoicePack.referenceName}');
      final legacyStyle = File('$dir${sep}style.wav');
      if (legacyStyle.existsSync()) {
        legacyStyle
            .copySync('${target.path}${sep}${VoicePack.styleName}');
      }
      final pack = VoicePack(
        id: target.uri.pathSegments.last.replaceAll(VoicePack.folderSuffix, ''),
        name: '我的声音',
        dir: target.path,
        referencePath: '${target.path}${sep}${VoicePack.referenceName}',
        stylePath: legacyStyle.existsSync()
            ? '${target.path}${sep}${VoicePack.styleName}'
            : null,
        createdAt: DateTime.now(),
        referenceSeconds: _seconds(
            '${target.path}${sep}${VoicePack.referenceName}'),
        engine: engine,
      );
      File('${target.path}${sep}${VoicePack.manifestName}')
          .writeAsStringSync(pack.manifestJson, flush: true);
      ErrorLogger.log(
          '[voice-pack] migrated my_voice.wav -> ${pack.dir}', null,
          source: 'voice-pack');
      return VoicePack.fromDirectory(target);
    } catch (e) {
      ErrorLogger.log(e, null, source: 'voice-pack');
      return null;
    }
  }

  /// Remove a pack. It goes to the recycle bin: a wrong click costs nothing.
  Future<bool> delete(VoicePack pack) async {
    if (!Directory(pack.dir).existsSync()) return true;
    final path = pack.dir.replaceAll('"', '""');
    final script = '''
Add-Type -AssemblyName Microsoft.VisualBasic
try {
  [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
    "$path",
    [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
    [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
  Write-Output 1
} catch {
  Write-Output 0
}
''';
    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
      );
      return '${result.stdout}'.trim() == '1';
    } catch (e) {
      ErrorLogger.log(e, null, source: 'voice-pack');
      return false;
    }
  }
}
