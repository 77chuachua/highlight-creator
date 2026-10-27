import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/app_paths.dart';
import 'package:highlight_creator/services/voice_service.dart';

/// Builds a minimal RIFF/WAVE file: 16-bit mono PCM at [sampleRate].
Uint8List buildWav({required int sampleRate, required int samples}) {
  const headerSize = 44;
  final dataSize = samples * 2;
  final bytes = Uint8List(headerSize + dataSize);
  final data = ByteData.sublistView(bytes);

  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      bytes[offset + i] = text.codeUnitAt(i);
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + dataSize, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little); // fmt chunk size
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  data.setUint16(32, 2, Endian.little); // block align
  data.setUint16(34, 16, Endian.little); // bits per sample
  ascii(36, 'data');
  data.setUint32(40, dataSize, Endian.little);
  return bytes;
}

void main() {
  group('wavDuration', () {
    test('reads the duration from the data chunk', () {
      final dir = Directory.systemTemp.createTempSync('wav_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}\\a.wav';
      // One second of 16 kHz mono.
      File(path).writeAsBytesSync(buildWav(sampleRate: 16000, samples: 16000));

      final duration = VoiceService.wavDuration(path);
      expect(duration.inMilliseconds, 1000);
    });

    test('a file that is not a WAVE reads as zero', () {
      final dir = Directory.systemTemp.createTempSync('wav_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}\\b.bin';
      File(path).writeAsStringSync('not audio at all');

      expect(VoiceService.wavDuration(path), Duration.zero);
    });

    test('a missing file reads as zero instead of throwing', () {
      expect(VoiceService.wavDuration(r'C:\no\such\file.wav'), Duration.zero);
    });
  });

  group('personal voice', () {
    test('is reported once the recording exists', () {
      final dir = Directory.systemTemp.createTempSync('voice_');
      addTearDown(() => dir.deleteSync(recursive: true));
      AppPaths.overrideBaseDir = dir.path;
      addTearDown(() => AppPaths.overrideBaseDir = null);

      expect(VoiceService.hasPersonalVoice, isFalse);

      final file = File(VoiceService.personalVoicePath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(buildWav(sampleRate: 44100, samples: 44100));

      expect(VoiceService.hasPersonalVoice, isTrue);
      expect(VoiceService.personalVoicePath,
          endsWith('my_voice.wav'));
    });
  });
}
