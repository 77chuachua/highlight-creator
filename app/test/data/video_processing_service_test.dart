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

  group('textYExpr', () {
    // Every design set draws its text plate centered at H*0.46 (see
    // _nocturneLayers), so frame-centered text lands visibly low in the band.
    test('middle targets the plate center, not the frame center', () {
      expect(VideoProcessingService.textYExpr('middle'), 'h*0.46-text_h/2');
      expect(VideoProcessingService.textYExpr(null), 'h*0.46-text_h/2');
    });

    test('a transition keeps its reserved zone at the frame center', () {
      expect(VideoProcessingService.textYExpr('middle', transition: true),
          '(h-text_h)/2');
    });

    test('top and bottom are unchanged', () {
      expect(VideoProcessingService.textYExpr('top'), 'h*0.15');
      expect(VideoProcessingService.textYExpr('bottom'), 'h*0.85-text_h');
    });
  });
}