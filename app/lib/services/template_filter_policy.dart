/// Decides whether a downloaded ffmpeg filtergraph may run on this machine.
///
/// A template plugin is a filtergraph fetched from the internet, and a
/// filtergraph is a small language. Handing an arbitrary one to ffmpeg would
/// hand a GitHub manifest the ability to read the user's disk (`movie=`,
/// `drawtext=textfile=`), so every filter is checked against an explicit
/// allowlist before the process starts.
///
/// The allowlist doubles as a licence gate. It was derived from what this
/// build actually compiles in, which means the GPL-licensed filters (`eq`,
/// `boxblur`, `hqdn3d`, `delogo`, `pp*`, `frei0r*`, `ocr`, `vidstab*`) are
/// absent by construction — naming one here would only produce a plugin that
/// fails on the LGPL ffmpeg we ship.
class TemplateFilterPolicy {
  /// lavfi sources a plugin may build its input from.
  static const Set<String> allowedSources = {
    'color',
    'anullsrc',
    'nullsrc',
  };

  static const Set<String> allowedFilters = {
    // Video
    'format', 'geq', 'scale', 'fps', 'fade', 'drawtext', 'drawbox',
    'trim', 'setpts', 'split', 'copy', 'setsar', 'pad', 'crop', 'overlay',
    'negate', 'curves', 'hue', 'colorchannelmixer', 'colorbalance', 'rotate',
    'loop', 'reverse', 'select', 'tile', 'hstack', 'vstack',
    // Audio
    'volume', 'afade', 'aformat', 'aresample', 'apad', 'atrim', 'asetpts',
    'amerge', 'channelsplit',
  };

  /// Options that turn a filter into a file reader. `drawtext` is allowed for
  /// typography, but only with an inline `text=`; `textfile=` would let a
  /// plugin render any file on the machine into the user's video.
  /// Filtergraphs are passed to ffmpeg on the command line, and Windows caps a
  /// command line at 32767 characters. The built-in nocturne scene is ~14 kB,
  /// so this leaves room for a far richer plugin while still failing loudly
  /// instead of producing a truncated command.
  static const int maxGraphChars = 30000;

  static const Set<String> forbiddenOptions = {
    'textfile',
    'movie',
    'amovie',
    'filename',
  };

  static bool isAllowed(String name) =>
      allowedSources.contains(name) || allowedFilters.contains(name);

  /// Split a filtergraph on its top-level commas.
  ///
  /// A naive `split(',')` is wrong and unsafe here: `geq` arguments are full of
  /// commas, and so is any `drawtext` with real copy in it. Three things must
  /// be tracked — single quotes (which ffmpeg uses to protect commas), the
  /// backslash escapes *inside* those quotes, and parenthesis depth.
  static List<String> splitChain(String graph) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    var quoted = false;
    for (var i = 0; i < graph.length; i++) {
      final c = graph[i];
      if (quoted) {
        buf.write(c);
        if (c == r'\' && i + 1 < graph.length) {
          // Escaped character: consume both, so `\,` never ends the argument.
          buf.write(graph[++i]);
        } else if (c == "'") {
          quoted = false;
        }
        continue;
      }
      switch (c) {
        case "'":
          quoted = true;
          buf.write(c);
        case '(':
          depth++;
          buf.write(c);
        case ')':
          depth--;
          buf.write(c);
        case r'\':
          buf.write(c);
          if (i + 1 < graph.length) buf.write(graph[++i]);
        case ',':
          if (depth == 0) {
            out.add(buf.toString());
            buf.clear();
          } else {
            buf.write(c);
          }
        default:
          buf.write(c);
      }
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) out.add(tail);
    return out.where((s) => s.trim().isNotEmpty).toList();
  }

  /// Leading identifier of one chain component: `geq=r='...'` -> `geq`.
  ///
  /// Stops at the first `=` or `:` so a filter named in an *argument* cannot
  /// be mistaken for the filter itself.
  static String? componentName(String component) {
    final m = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)').firstMatch(component.trim());
    return m?.group(1);
  }

  /// Validate [rawGraph], returning the first violation or null when clean.
  ///
  /// Leading/trailing whitespace is tolerated because a script served from a
  /// repo almost always ends in a newline, but an *interior* newline is not:
  /// the graph goes on the command line as one argument.
  static String? validate(String rawGraph) {
    final graph = rawGraph.trim();
    if (graph.isEmpty) return 'the script is empty';
    if (graph.contains('\n') || graph.contains('\r')) {
      return 'the script must be a single line (no interior newlines)';
    }
    if (graph.length > maxGraphChars) {
      return 'script is ${graph.length} characters; the limit is '
          '$maxGraphChars because it is passed to ffmpeg on the command line';
    }
    if (splitChain(graph).isEmpty) return 'the script contains no filters';

    for (final raw in splitChain(graph)) {
      final component = raw.trim();
      final name = componentName(component);
      if (name == null) {
        return 'cannot parse filter chain near "${_clip(component)}"';
      }
      if (!isAllowed(name)) {
        return 'filter "$name" is not allowed. Allowed: '
            '${(allowedFilters.toList()..sort()).take(12).join(', ')}, ... '
            '(see TemplateFilterPolicy)';
      }
      // Options appear as `name=value`; only look after the first separator so
      // an `=` inside a quoted argument is not mistaken for an option.
      for (final opt in _optionsOf(component)) {
        if (forbiddenOptions.contains(opt)) {
          return '"$name=$opt" is not allowed — it reads local files. '
              'Use inline values instead.';
        }
      }
    }
    return null;
  }

  /// Option keys in one component, skipping anything inside quotes.
  static Set<String> _optionsOf(String component) {
    final opts = <String>{};
    var quoted = false;
    for (var i = 0; i < component.length; i++) {
      final c = component[i];
      if (quoted) {
        if (c == r'\' && i + 1 < component.length) {
          i++;
        } else if (c == "'") {
          quoted = false;
        }
        continue;
      }
      if (c == "'") {
        quoted = true;
        continue;
      }
      if (c == '=' || c == ':') {
        var j = i + 1;
        final key = StringBuffer();
        while (j < component.length &&
            RegExp(r'[A-Za-z0-9_]').hasMatch(component[j])) {
          key.write(component[j]);
          j++;
        }
        if (key.isNotEmpty) {
          opts.add(key.toString());
        }
        i = j - 1;
      }
    }
    return opts;
  }

  static String _clip(String s) =>
      s.length <= 40 ? s : '${s.substring(0, 40)}...';
}
