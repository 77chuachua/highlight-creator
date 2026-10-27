import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/data/cache_catalog.dart';

/// The cache dialog deletes whatever this says is a Make intermediate, and
/// `results\final.mp4` is the thing you watch afterwards: a wrong pattern here
/// loses deliverables.
void main() {
  group('isMakeIntermediate', () {
    test('matches what Make re-renders on every run', () {
      for (final name in [
        'slot_0_sub.mp4',
        'slot_12_transition.mp4',
        'slot_53_sub.mp4',
        'body.mp4',
        'body_music.mp4',
        'startup_normalized.mp4',
        'startup_titled.mp4',
        'ending_normalized.mp4',
      ]) {
        expect(isMakeIntermediate(name), isTrue, reason: name);
      }
    });

    test('never matches a deliverable or a project file', () {
      for (final name in [
        'final.mp4',
        'week_2026-W43_goal_top5.mp4',
        'week_2026-W43_1.mp4',
        'month_2026-10_save_top5.mp4',
        'year_2026_goal_top10.mp4',
        '2026-10-23.hlcproj',
        'body.mp4.tmp',
        'slot_1_sub.mp4.bak',
        'slot_sub.mp4',
        'bodycopy.mp4',
      ]) {
        expect(isMakeIntermediate(name), isFalse, reason: name);
      }
    });

    test('is case and separator agnostic about the name only', () {
      // The dialog passes the bare file name, never a path.
      expect(isMakeIntermediate('BODY.MP4'), isFalse);
      expect(isMakeIntermediate(r'slot_1\sub.mp4'), isFalse);
    });
  });
}
