import 'package:flutter_test/flutter_test.dart';
import 'package:highlight_creator/services/template_filter_policy.dart';

/// The filter allowlist is the boundary between "a template someone published"
/// and "code running on the user's machine", so it gets tested adversarially:
/// every case below is an attempt to get a disallowed filter past the parser.
void main() {
  group('splitChain', () {
    test('splits on top-level commas only', () {
      expect(
        TemplateFilterPolicy.splitChain('format=rgb24,geq=r=X,g=Y,fps=30'),
        ['format=rgb24', 'geq=r=X', 'g=Y', 'fps=30'],
      );
    });

    test('keeps commas inside geq arguments together', () {
      // The real nocturne scene: geq arguments are dense with commas and would
      // be shredded by a naive split.
      const graph = r"geq=r='max(0\,1-X/W)':g='min(255\,X*2)':b='128',fps=30";
      expect(TemplateFilterPolicy.splitChain(graph).length, 2);
      expect(TemplateFilterPolicy.splitChain(graph).first, contains('geq'));
    });

    test('keeps commas inside quoted drawtext copy together', () {
      const graph = "drawtext=text='Week 12, Day 3':fontsize=48,fade=t=in";
      expect(TemplateFilterPolicy.splitChain(graph).length, 2);
      expect(TemplateFilterPolicy.splitChain(graph).first,
          contains('Week 12, Day 3'));
    });

    test('honours backslash-escaped commas inside quotes', () {
      const graph = r"drawtext=text='a\,b',fps=30";
      expect(TemplateFilterPolicy.splitChain(graph).length, 2);
    });

    test('tracks nested parentheses', () {
      const graph = r"geq=r='if(gt(X\,W/2)\,200\,40)',fps=30";
      expect(TemplateFilterPolicy.splitChain(graph).length, 2);
    });

    test('empty and whitespace-only components are dropped', () {
      expect(TemplateFilterPolicy.splitChain('fps=30,,'), ['fps=30']);
      expect(TemplateFilterPolicy.splitChain('   '), isEmpty);
    });
  });

  group('validate accepts legitimate graphs', () {
    test('a built-in-style scene passes', () {
      const graph = 'format=rgb24,'
          "geq=r='20+40*(Y/H)':g='30+50*(Y/H)':b='60+60*(Y/H)',"
          'format=yuv420p,scale=1280:720:flags=lanczos,fps=30,'
          'fade=t=in:st=0:d=0.5,fade=t=out:st=3.4:d=0.6';
      expect(TemplateFilterPolicy.validate(graph), isNull);
    });

    test('inline drawtext copy with commas is allowed', () {
      const graph = "drawtext=text='Goal, 90+3':fontsize=64,fade=t=out";
      expect(TemplateFilterPolicy.validate(graph), isNull);
    });

    test('lavfi sources are allowed as chain members', () {
      expect(TemplateFilterPolicy.validate('color=c=black,fade=t=out'), isNull);
    });
  });

  group('validate rejects', () {
    test('file-reading filters', () {
      for (final bad in [
        'movie=/etc/passwd,fps=30',
        'amovie=C\\:/secret.mp4,fps=30',
      ]) {
        final why = TemplateFilterPolicy.validate(bad);
        expect(why, isNotNull, reason: bad);
        expect(why, contains('not allowed'), reason: bad);
      }
    });

    test('GPL filters this build does not compile', () {
      // Present in a GPL ffmpeg, absent from the LGPL one we ship. Allowing
      // them would only produce a template that fails at render time.
      for (final gpl in ['eq=contrast=1.2', 'boxblur=2:1', 'hqdn3d=2:2:3']) {
        expect(TemplateFilterPolicy.validate('$gpl,fps=30'), isNotNull,
            reason: gpl);
      }
    });

    test('a disallowed filter hidden after an allowed one', () {
      final why = TemplateFilterPolicy.validate('fade=t=in,movie=/x.mp4');
      expect(why, contains('movie'));
    });

    test('drawtext reading a local file via textfile', () {
      final why = TemplateFilterPolicy.validate(
          "drawtext=textfile='C\\:/Windows/win.ini':fontsize=24");
      expect(why, contains('textfile'));
      expect(why, contains('reads local files'));
    });

    test('an over-long graph, because it is inlined on the command line', () {
      final graph = 'geq=r=${'9' * (TemplateFilterPolicy.maxGraphChars + 1)}';
      expect(TemplateFilterPolicy.validate(graph), contains('command line'));
    });

    test('newlines, which would truncate the argument', () {
      expect(TemplateFilterPolicy.validate('fps=30\ncrop=10:10'), isNotNull);
    });

    test('an empty script', () {
      expect(TemplateFilterPolicy.validate('   '), isNotEmpty);
    });
  });

  group('componentName', () {
    test('stops at the first separator so arguments cannot impersonate filters',
        () {
      expect(TemplateFilterPolicy.componentName('geq=r=X'), 'geq');
      expect(TemplateFilterPolicy.componentName('scale=1280:720'), 'scale');
      expect(TemplateFilterPolicy.componentName('1bad=x'), isNull);
    });
  });

  group('allowlist contents', () {
    test('covers what the built-in generators actually use', () {
      // If a future built-in set starts using a filter, the allowlist has to
      // grow with it or plugins cannot express the same look.
      for (final used in [
        'format',
        'geq',
        'scale',
        'fps',
        'fade',
        'drawtext',
        'drawbox',
        'overlay',
        'volume',
        'afade',
        'aformat',
        'aresample',
        'apad',
        'anullsrc',
        'color',
        'trim',
        'setpts',
        'copy',
        'setsar',
        'pad',
        'crop',
      ]) {
        expect(TemplateFilterPolicy.isAllowed(used), isTrue, reason: used);
      }
    });

    test('does not contain any GPL-gated filter', () {
      for (final gpl in [
        'eq',
        'boxblur',
        'hqdn3d',
        'delogo',
        'pp',
        'pp7',
        'frei0r',
        'vidstabdetect',
        'vidstabtransform',
        'ocr',
        'signature',
      ]) {
        expect(TemplateFilterPolicy.isAllowed(gpl), isFalse, reason: gpl);
      }
    });
  });
}
