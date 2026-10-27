import 'dart:convert';
import 'dart:io';

/// One voice the user created with the voice-cloning plugin.
///
/// A pack is a folder: `voices\<name>.voicepack\` holding the reference
/// recording, an optional intonation reference, and a manifest. Packs are
/// portable — copying the folder to another machine is the whole "install".
class VoicePack {
  /// Folder name without the `.voicepack` suffix; stable across renames.
  final String id;

  /// Display name from the manifest, falling back to the folder name.
  final String name;

  final String dir;
  final String referencePath;

  /// Optional clip whose intonation the engine copies.
  final String? stylePath;

  final DateTime? createdAt;

  /// Length of the reference recording, when the manifest records it.
  final double referenceSeconds;

  /// The engine that made the pack, for the install-guide hint.
  final String engine;

  /// Delivery settings recorded in the studio, so picking this pack in the
  /// app reproduces the voice that was auditioned there.
  final double speed;

  /// Free-form tone instruction ("用激动的语气喊出这句话").
  final String instruct;

  /// Transcript of the reference recording; the engine aligns against it.
  final String promptText;

  const VoicePack({
    required this.id,
    required this.name,
    required this.dir,
    required this.referencePath,
    this.stylePath,
    this.createdAt,
    this.referenceSeconds = 0,
    this.engine = '',
    this.speed = 1,
    this.instruct = '',
    this.promptText = '',
  });

  bool get hasStyle => stylePath != null;

  /// "我的声音 · 12.5 秒"
  String get label => referenceSeconds > 0
      ? '$name · ${referenceSeconds.toStringAsFixed(1)} 秒'
      : name;

  static const folderSuffix = '.voicepack';
  static const manifestName = 'manifest.json';
  static const referenceName = 'reference.wav';
  static const styleName = 'style.wav';
  static const previewName = 'preview.wav';

  /// Read one pack folder, or null when it has no usable reference.
  static VoicePack? fromDirectory(Directory folder) {
    final reference = File(
        '${folder.path}${Platform.pathSeparator}$referenceName');
    if (!reference.existsSync()) return null;
    final id = folder.uri.pathSegments
        .lastWhere((s) => s.isNotEmpty, orElse: () => folder.path)
        .replaceAll(folderSuffix, '');
    Map<String, dynamic> manifest = const {};
    try {
      final file =
          File('${folder.path}${Platform.pathSeparator}$manifestName');
      if (file.existsSync()) {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map<String, dynamic>) manifest = decoded;
      }
    } catch (_) {
      // A broken manifest must not hide the audio: fall back to defaults.
    }
    final style =
        File('${folder.path}${Platform.pathSeparator}$styleName');
    final createdAtRaw = manifest['createdAt'];
    return VoicePack(
      id: id,
      name: (manifest['name'] as String?)?.trim().isNotEmpty == true
          ? (manifest['name'] as String).trim()
          : id,
      dir: folder.path,
      referencePath: reference.path,
      stylePath: style.existsSync() ? style.path : null,
      createdAt: createdAtRaw is String
          ? DateTime.tryParse(createdAtRaw)
          : null,
      referenceSeconds:
          (manifest['referenceSeconds'] as num?)?.toDouble() ?? 0,
      engine: (manifest['engine'] as String?) ?? '',
      speed: (manifest['speed'] as num?)?.toDouble() ?? 1,
      instruct: (manifest['instruct'] as String?) ?? '',
      promptText: (manifest['promptText'] as String?) ?? '',
    );
  }

  String get manifestJson => const JsonEncoder.withIndent('  ').convert({
        'schema': 1,
        'name': name,
        'createdAt': (createdAt ?? DateTime.now()).toIso8601String(),
        'engine': engine,
        'referenceSeconds': referenceSeconds,
        'sampleRate': 44100,
        'speed': speed,
        'instruct': instruct,
        'promptText': promptText,
      });
}
