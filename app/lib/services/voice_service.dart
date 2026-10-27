import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'package:highlight_creator/data/app_paths.dart';

/// One speech voice Windows has installed.
class SystemVoice {
  final String id;
  final String name;
  final String locale;
  final String gender;

  /// Server voices are the network ones; everything else is local and works
  /// without a connection.
  final bool local;

  const SystemVoice({
    required this.id,
    required this.name,
    required this.locale,
    required this.gender,
    required this.local,
  });

  factory SystemVoice.fromMap(Map<Object?, Object?> map) => SystemVoice(
        id: (map['id'] as String?) ?? '',
        name: (map['name'] as String?) ?? '',
        locale: (map['locale'] as String?) ?? '',
        gender: (map['gender'] as String?) ?? '',
        local: (map['local'] as bool?) ?? true,
      );

  /// "Microsoft Huihui Desktop · zh-CN"
  String get label => '$name · $locale';
}

/// The audio of one synthesized clip.
class VoiceClip {
  final String path;
  final Duration duration;

  const VoiceClip(this.path, this.duration);
}

/// Renders text with the voices Windows ships with.
///
/// The voices are the ones the user installed (Narrator voices in Settings, or
/// a language speech pack), so the list changes as they add packs. Everything
/// runs offline: no key, no network, and the audio never leaves the machine.
class VoiceService {
  static const MethodChannel _channel = MethodChannel('highlight_creator/speech');

  /// Id of the user's own recorded voice in the picker.
  static const personalVoiceId = '__my_voice__';

  /// Label of the user's own voice in the picker.
  static const personalVoiceName = '我的声音';

  /// The text the user reads when recording their own voice.
  ///
  /// The cloning model needs to know what the recording says, so this exact
  /// sentence is handed to the engine as the prompt text.
  static const personalVoicePrompt =
      '欢迎来到本周最佳进球时刻，让我们一起回顾赛场上的每一个精彩瞬间。';

  /// Where the user's own voice is kept.
  static String get personalVoicePath =>
      '${AppPaths.baseDir}${Platform.pathSeparator}voices'
      '${Platform.pathSeparator}my_voice.wav';

  /// Whether the user already recorded their own voice.
  static bool get hasPersonalVoice => File(personalVoicePath).existsSync();

  /// Optional intonation reference: a clip whose delivery the engine copies
  /// while it keeps the user's own timbre (see LocalVoiceService.speak).
  static String get styleReferencePath =>
      '${AppPaths.baseDir}${Platform.pathSeparator}voices'
      '${Platform.pathSeparator}style.wav';

  /// Whether the user has picked an intonation reference.
  static bool get hasStyleReference => File(styleReferencePath).existsSync();

  /// Installed voices, local ones first, then sorted by name.
  ///
  /// Every voice the machine has is listed - the user picks the one they want,
  /// and the guide dialog explains how to add more. Returns an empty list when
  /// the platform has no speech support (or the channel is missing), so the
  /// caller can hide the picker instead of failing.
  static Future<List<SystemVoice>> voices({String languagePrefix = ''}) async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>(
        'voices',
        {'languagePrefix': languagePrefix},
      );
      final voices = <SystemVoice>[
        for (final item in raw ?? const <Object?>[])
          if (item is Map<Object?, Object?>) SystemVoice.fromMap(item),
      ];
      voices.sort((a, b) {
        if (a.local != b.local) return a.local ? -1 : 1;
        return a.name.compareTo(b.name);
      });
      return voices;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  /// Renders [text] with [voiceId] into a WAV file at [outputPath].
  ///
  /// Returns null when the platform cannot synthesize or the voice is unknown;
  /// the caller keeps the reel going without narration in that case.
  static Future<VoiceClip?> synthesize({
    required String text,
    required String voiceId,
    required String outputPath,
    int rate = 0,
  }) async {
    if (text.trim().isEmpty) return null;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'synthesize',
        {
          'text': text,
          'voiceId': voiceId,
          'rate': rate,
          'outputPath': outputPath,
        },
      );
      if (raw == null || raw['ok'] != true) return null;
      final path = (raw['path'] as String?) ?? outputPath;
      if (!File(path).existsSync()) return null;
      return VoiceClip(path, wavDuration(path));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Duration of a RIFF/WAVE file, from its data chunk.
  ///
  /// The synthesized stream can carry a placeholder RIFF size, so the data
  /// chunk is what counts. Returns [Duration.zero] when the file is not a
  /// readable WAVE.
  static Duration wavDuration(String path) {
    try {
      final bytes = File(path).readAsBytesSync();
      if (bytes.length < 44) return Duration.zero;
      final data = ByteData.sublistView(bytes);
      if (String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
        return Duration.zero;
      }
      var offset = 12;
      var byteRate = 0;
      var dataSize = 0;
      while (offset + 8 <= bytes.length) {
        final chunk = String.fromCharCodes(bytes.sublist(offset, offset + 4));
        final size = data.getUint32(offset + 4, Endian.little);
        if (chunk == 'fmt ' && offset + 8 + 16 <= bytes.length) {
          byteRate = data.getUint32(offset + 8 + 8, Endian.little);
        } else if (chunk == 'data') {
          dataSize = size;
          break;
        }
        offset += 8 + size + (size.isOdd ? 1 : 0);
      }
      if (byteRate <= 0 || dataSize <= 0) return Duration.zero;
      final micros = (dataSize * 1000000) ~/ byteRate;
      return Duration(microseconds: micros);
    } catch (_) {
      return Duration.zero;
    }
  }
}
