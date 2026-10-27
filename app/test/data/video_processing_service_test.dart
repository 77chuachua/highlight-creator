import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/ffi/video_processing_service.dart';
import 'package:highlight_creator/domain/entities/timeslot.dart';

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

  group('slotCaption', () {
    // The caption is both the transition card's text and the clip's
    // bottom-left watermark, so its shape is a contract: "01 xx助攻xx".
    test('prefixes the 1-based sequence number, two digits', () {
      expect(VideoProcessingService.slotCaption(0, 'xx助攻xx'), '01 xx助攻xx');
      expect(VideoProcessingService.slotCaption(22, 'xx没收皮球'), '23 xx没收皮球');
    });

    test('an empty description leaves just the number', () {
      expect(VideoProcessingService.slotCaption(0, ''), '01');
      expect(VideoProcessingService.slotCaption(4, '   '), '05');
    });

    test('a wider index widens the prefix instead of truncating', () {
      expect(VideoProcessingService.slotCaption(99, 'a'), '100 a');
    });

    test('trims the description but keeps its inner spacing', () {
      expect(VideoProcessingService.slotCaption(2, '  快攻 得分  '), '03 快攻 得分');
    });
  });

  group('slotWindow', () {
    // Make and the Top-5 flow both cut from this window; if they drift the two
    // features produce different clips from the same slot.
    Timeslot slot({required int inMs, int elapse = 0, int outMs = 0}) =>
        Timeslot(
          id: 'a',
          projectId: 'p',
          videoSourceId: 'v',
          inPointMs: inMs,
          outPointMs: outMs == 0 ? inMs : outMs,
          elapse: elapse,
          createdAt: DateTime(2026, 10, 14),
        );

    test('an explicit elapse uses its own window', () {
      final window = VideoProcessingService.slotWindow(
          slot(inMs: 30000, outMs: 45000, elapse: 12000));
      expect(window.start, 30.0);
      expect(window.duration, 12.0);
    });

    test('a legacy point-mark covers the 10 seconds before it', () {
      final window = VideoProcessingService.slotWindow(slot(inMs: 45000));
      expect(window.start, 35.0);
      expect(window.duration, 10.0);
    });

    test('a mark inside the first 10 seconds starts at zero', () {
      final window = VideoProcessingService.slotWindow(slot(inMs: 4000));
      expect(window.start, 0.0);
      expect(window.duration, 4.0);
    });
  });

  // The Top-5 reel reuses Make's rendered slices and paints over the caption
  // Make burned into them. These numbers come from measuring a real 4K frame
  // (results/slot_0_sub.mp4, caption "01 老庄没收皮球"): the glyphs sit at
  // x 88..664, y 2000..2075 on a 3840x2160 frame.
  group('caption watermark geometry', () {
    const caption = '01 老庄没收皮球';

    test('em width matches the measured render within 2%', () {
      // Measured: 577 px wide at font size 78 → 7.40 em.
      final em = VideoProcessingService.captionEmWidth(caption);
      expect(em, closeTo(7.40, 0.15));
    });

    test('digits and CJK stay distinguishable', () {
      expect(VideoProcessingService.captionEmWidth('01'),
          closeTo(1.10, 0.01));
      expect(VideoProcessingService.captionEmWidth('助攻'), closeTo(2.0, 0.01));
    });

    test('the 4K box covers the measured pixels', () {
      final box = VideoProcessingService.captionBox(
        text: caption,
        frameWidth: 3840,
        frameHeight: 2160,
      );
      // Measured pixel extents of the text.
      expect(box.x, lessThanOrEqualTo(88));
      expect(box.x + box.width, greaterThanOrEqualTo(664));
      expect(box.y, lessThanOrEqualTo(2000));
      expect(box.y + box.height, greaterThanOrEqualTo(2075));
    });

    test('the box stays inside the frame even for a long caption', () {
      final box = VideoProcessingService.captionBox(
        text: '01 这是一个特别特别长的解说词用来测试边界处理是否安全可靠',
        frameWidth: 1280,
        frameHeight: 720,
      );
      expect(box.x, greaterThanOrEqualTo(0));
      expect(box.y, greaterThanOrEqualTo(0));
      expect(box.x + box.width, lessThanOrEqualTo(1280));
      expect(box.y + box.height, lessThanOrEqualTo(720));
    });
  });

  // The Top-5 preview uses this probe to decide whether a cached clip is real.
  // A cut that was interrupted leaves a file that exists but carries no usable
  // video, and trusting "the file exists" is what made the same clip refuse to
  // preview forever.
  group('probeDurationMs rejects unusable clips', () {
    String scratch(String name) {
      final dir = Directory.systemTemp.createTempSync('hl_probe_');
      addTearDown(() => dir.deleteSync(recursive: true));
      return '${dir.path}${Platform.pathSeparator}$name';
    }

    test('a truncated clip does not read as playable', () async {
      final path = scratch('stub.mp4');
      // An ftyp box followed by nothing: what a killed ffmpeg leaves behind.
      File(path).writeAsBytesSync(<int>[
        0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, 0x69, 0x73, 0x6f, 0x6d,
        ...List<int>.filled(2048, 0),
      ]);

      final ms = await VideoProcessingService.probeDurationMs(path);
      expect(ms == null || ms <= 0, isTrue,
          reason: 'a half-written clip must not count as playable');
    });

    test('an empty file does not read as playable', () async {
      final path = scratch('empty.mp4');
      File(path).writeAsBytesSync(const <int>[]);

      final ms = await VideoProcessingService.probeDurationMs(path);
      expect(ms == null || ms <= 0, isTrue);
    });

    test('a real clip still reports a positive duration', () async {
      final ffmpeg = await VideoProcessingService.findFfmpeg();
      if (ffmpeg == null) return; // CI has no bundled ffmpeg
      final path = scratch('real.mp4');
      final made = await Process.run(ffmpeg, <String>[
        '-y',
        '-f', 'lavfi', '-i', 'color=c=black:s=160x90:d=1',
        '-c:v', 'mpeg4', '-t', '1',
        path,
      ]);
      expect(made.exitCode, 0, reason: 'ffmpeg could not build the fixture');

      final ms = await VideoProcessingService.probeDurationMs(path);
      expect(ms, isNotNull);
      expect(ms! > 0, isTrue,
          reason: 'the probe must keep accepting good clips');
    });
  });
}
