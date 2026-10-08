import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';

/// Pure parsing logic of the video metadata probe (no ffmpeg needed).
void main() {
  group('parseAvgFrameRate', () {
    test('parses ffprobe rational frame rates', () {
      expect(VideoProcessingService.parseAvgFrameRate('30000/1001'),
          closeTo(29.97, 0.01));
    });

    test('parses plain numbers', () {
      expect(VideoProcessingService.parseAvgFrameRate('60'), 60.0);
      expect(VideoProcessingService.parseAvgFrameRate('30'), 30.0);
    });

    test('returns 0 on garbage', () {
      expect(VideoProcessingService.parseAvgFrameRate('abc'), 0);
      expect(VideoProcessingService.parseAvgFrameRate(''), 0);
    });

    test('handles division by zero', () {
      expect(VideoProcessingService.parseAvgFrameRate('30/0'), 0);
    });
  });
}