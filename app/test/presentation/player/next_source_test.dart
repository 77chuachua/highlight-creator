import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/presentation/player/player_view_model.dart';

/// Pure logic behind chained playback (issues.md): which source plays next
/// after the current one finishes. No media_kit native resources involved.
void main() {
  VideoSource src(String id, String path) => VideoSource(
        id: id,
        projectId: 'p',
        filePath: path,
        durationMs: 10000,
        width: 0,
        height: 0,
        codecName: '',
        fps: 0,
        createdAt: DateTime(2026),
      );

  const dir = r'C:\videos';
  final sources = [
    src('a', '$dir\\a.mp4'),
    src('b', '$dir\\b.mp4'),
    src('c', '$dir\\c.mp4'),
  ];

  test('returns the next source after the current one', () {
    expect(nextSourcePath(sources, '$dir\\a.mp4'), '$dir\\b.mp4');
    expect(nextSourcePath(sources, '$dir\\b.mp4'), '$dir\\c.mp4');
  });

  test('returns null for the last source', () {
    expect(nextSourcePath(sources, '$dir\\c.mp4'), isNull);
  });

  test('returns null when the current path is not a project source', () {
    expect(nextSourcePath(sources, '$dir\\other.mp4'), isNull);
    expect(nextSourcePath(sources, 'startup.mp4'), isNull);
  });

  test('matches by file name when the path differs but the name matches', () {
    expect(
      nextSourcePath(sources, r'C:\temp\copied\b.mp4'),
      '$dir\\c.mp4',
    );
  });

  test('single source and empty lists never chain', () {
    expect(nextSourcePath([sources.first], '$dir\\a.mp4'), isNull);
    expect(nextSourcePath(const [], '$dir\\a.mp4'), isNull);
    expect(nextSourcePath(sources, ''), isNull);
  });
}