import 'package:highlight_creator/domain/entities/template.dart';

/// Manifest schema version this build understands.
///
/// Bumped only for breaking changes; unknown *fields* are ignored so an author
/// can add metadata without every older build refusing the file.
const int kTemplateManifestSchema = 1;

/// A downloadable template described by a remote [TemplateManifest].
///
/// The visual definition is not inline: it lives in a separate ffmpeg
/// filtergraph ([script]) that is fetched on demand, so browsing the catalogue
/// costs one small JSON request rather than every template's source.
class RemoteTemplateSpec {
  /// Stable identifier, unique within a manifest. Also the on-disk cache key,
  /// so it must be filename-safe.
  final String id;

  /// Human-facing name shown on the card.
  final String name;

  /// One-line description shown under the name.
  final String description;

  /// Attribution shown on the card.
  final String author;

  final TemplateType type;

  /// Optional thumbnail. Purely cosmetic: a broken URL must never stop the
  /// template from generating, so the UI treats it as best-effort.
  final String? previewUrl;

  final RemoteScriptRef script;
  final RemoteRenderSpec render;

  const RemoteTemplateSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.author,
    required this.type,
    required this.script,
    required this.render,
    this.previewUrl,
  });

  /// Filename-safe identity used for the cached script and rendered video.
  ///
  /// The manifest revision is part of the name so that publishing a new script
  /// invalidates the cache by changing the path — no sidecar bookkeeping and
  /// no stale video served after an author updates their template.
  String get cacheKey => 'plugin_${id}_${script.revision}';

  factory RemoteTemplateSpec.fromJson(
    Map<String, dynamic> json, {
    required int index,
  }) {
    final id = _reqString(json, 'id', index);
    if (!_isCacheSafe(id)) {
      throw TemplateManifestFormatException(
        'template #$index: id "$id" must be filename-safe '
        '(letters, digits, dot, dash, underscore)',
      );
    }
    final rawType = _reqString(json, 'type', index);
    final type = switch (rawType) {
      'startup' => TemplateType.startup,
      'transition' => TemplateType.transition,
      'ending' => TemplateType.ending,
      _ => throw TemplateManifestFormatException(
          'template "$id": unsupported type "$rawType" '
          '(expected startup, transition or ending)',
        ),
    };
    return RemoteTemplateSpec(
      id: id,
      name: _reqString(json, 'name', index),
      description: _optString(json, 'description') ?? '',
      author: _optString(json, 'author') ?? 'unknown',
      type: type,
      previewUrl: _optString(json, 'previewUrl'),
      script: RemoteScriptRef.fromJson(
        _reqObject(json, 'script', index, id),
        id: id,
      ),
      render: RemoteRenderSpec.fromJson(
        _reqObject(json, 'render', index, id),
        id: id,
      ),
    );
  }
}

/// Where a template's ffmpeg filtergraph lives, and how to prove the download
/// is the one the manifest promised.
class RemoteScriptRef {
  final String url;

  /// Lowercase hex SHA-256 of the script bytes. Optional, but without it the
  /// only integrity check is [sizeBytes] — a wrong-but-same-size file renders
  /// into a wrong template, which is worse than a loud failure.
  final String? sha256;

  /// Expected byte length. Always checked; cheap and catches truncated pulls.
  final int sizeBytes;

  /// Opaque author-controlled version string. Only its filename-safety and
  /// uniqueness matter — the app never interprets it.
  final String revision;

  const RemoteScriptRef({
    required this.url,
    required this.sizeBytes,
    required this.revision,
    this.sha256,
  });

  factory RemoteScriptRef.fromJson(Map<String, dynamic> json,
      {required String id}) {
    final url = _reqString(json, 'url', 0, owner: 'script of "$id"');
    // The URL is handed to HttpClient, so refuse anything that is not plain
    // HTTP(S). A `file://` or `data:` URL here would turn "download a template"
    // into "read an arbitrary local path".
    final lower = url.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      throw TemplateManifestFormatException(
        'script of "$id": url must start with http:// or https:// '
        '(got "${url.length > 40}...")',
      );
    }
    final sha = _optString(json, 'sha256')?.toLowerCase();
    if (sha != null && !RegExp(r'^[0-9a-f]{64}$').hasMatch(sha)) {
      throw TemplateManifestFormatException(
        'script of "$id": sha256 must be 64 lowercase hex characters',
      );
    }
    final size = _reqInt(json, 'sizeBytes', 0, owner: 'script of "$id"');
    if (size <= 0 || size > _maxScriptBytes) {
      throw TemplateManifestFormatException(
        'script of "$id": sizeBytes must be 1..$_maxScriptBytes (got $size)',
      );
    }
    final rev = _optString(json, 'revision') ?? sha?.substring(0, 12) ?? '1';
    if (!_isCacheSafe(rev)) {
      throw TemplateManifestFormatException(
        'script of "$id": revision "$rev" must be filename-safe',
      );
    }
    return RemoteScriptRef(
      url: url,
      sha256: sha,
      sizeBytes: size,
      revision: rev,
    );
  }

  /// Ceiling on a downloaded script. Generous next to the ~14 kB built-in
  /// scene, but bounded: the filtergraph is passed to ffmpeg on the command
  /// line, and Windows caps that at 32767 characters.
  static const int _maxScriptBytes = 262144;
}

/// How to turn the filtergraph into a finished clip.
class RemoteRenderSpec {
  final double durationSecs;
  final int width;
  final int height;

  /// Loop `bg_music.mp3` under the clip. Off by default: a plugin has no
  /// business shipping audio the user did not ask for.
  final bool withBgm;

  const RemoteRenderSpec({
    required this.durationSecs,
    required this.width,
    required this.height,
    required this.withBgm,
  });

  factory RemoteRenderSpec.fromJson(Map<String, dynamic> json,
      {required String id}) {
    final d = _optNum(json, 'durationSecs') ?? 4.0;
    if (d < 0.2 || d > 30.0) {
      throw TemplateManifestFormatException(
        'render of "$id": durationSecs must be 0.2..30 (got $d)',
      );
    }
    final w = _optInt(json, 'width') ?? 1280;
    final h = _optInt(json, 'height') ?? 720;
    if (w < 16 || h < 16 || w > 7680 || h > 4320 || w % 2 != 0 || h % 2 != 0) {
      throw TemplateManifestFormatException(
        'render of "$id": width/height must be even and within 16..7680 '
        'x 16..4320 (got ${w}x$h)',
      );
    }
    return RemoteRenderSpec(
      durationSecs: d,
      width: w,
      height: h,
      withBgm: _optBool(json, 'withBgm') ?? false,
    );
  }
}

/// The catalogue of downloadable templates.
class TemplateManifest {
  final int schemaVersion;
  final String? updatedAt;
  final List<RemoteTemplateSpec> templates;

  const TemplateManifest({
    required this.schemaVersion,
    required this.templates,
    this.updatedAt,
  });

  factory TemplateManifest.fromJson(Map<String, dynamic> json) {
    final v = _optInt(json, 'schemaVersion') ?? 1;
    if (v > kTemplateManifestSchema) {
      throw TemplateManifestFormatException(
        'manifest schemaVersion $v is newer than this build supports '
        '($kTemplateManifestSchema) — update Highlight Creator',
      );
    }
    final list = json['templates'];
    if (list is! List) {
      throw const TemplateManifestFormatException(
          'manifest is missing a "templates" array');
    }
    final specs = <RemoteTemplateSpec>[];
    final seen = <String>{};
    for (var i = 0; i < list.length; i++) {
      final entry = list[i];
      if (entry is! Map<String, dynamic>) {
        throw TemplateManifestFormatException('templates[$i] is not an object');
      }
      final spec = RemoteTemplateSpec.fromJson(entry, index: i);
      // Duplicate ids would collide in the on-disk cache: one template would
      // silently overwrite the other's video.
      if (!seen.add(spec.id)) {
        throw TemplateManifestFormatException(
            'duplicate template id "${spec.id}"');
      }
      specs.add(spec);
    }
    return TemplateManifest(
      schemaVersion: v,
      updatedAt: _optString(json, 'updatedAt'),
      templates: specs,
    );
  }
}

/// Thrown when a manifest exists but cannot be understood.
///
/// Distinct from a transport failure on purpose: a network error is the user's
/// connection, a format error is the author's file. They need different fixes.
class TemplateManifestFormatException implements Exception {
  final String reason;
  const TemplateManifestFormatException(this.reason);

  @override
  String toString() => reason;
}

bool _isCacheSafe(String s) =>
    s.isNotEmpty && s.length <= 64 && RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(s);

String? _optString(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is! String) {
    throw TemplateManifestFormatException('"$key" must be a string');
  }
  return v;
}

String _reqString(Map<String, dynamic> j, String key, int index,
    {String? owner}) {
  final v = _optString(j, key);
  if (v == null || v.isEmpty) {
    throw TemplateManifestFormatException(
      '${owner ?? 'template #$index'}: missing required "$key"',
    );
  }
  return v;
}

int? _optInt(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is! int) {
    throw TemplateManifestFormatException('"$key" must be an integer');
  }
  return v;
}

int _reqInt(Map<String, dynamic> j, String key, int index, {String? owner}) {
  final v = _optInt(j, key);
  if (v == null) {
    throw TemplateManifestFormatException(
      '${owner ?? 'template #$index'}: missing required "$key"',
    );
  }
  return v;
}

double? _optNum(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is! num) {
    throw TemplateManifestFormatException('"$key" must be a number');
  }
  return v.toDouble();
}

bool? _optBool(Map<String, dynamic> j, String key) {
  final v = j[key];
  if (v == null) return null;
  if (v is! bool) {
    throw TemplateManifestFormatException('"$key" must be true or false');
  }
  return v;
}

Map<String, dynamic> _reqObject(
    Map<String, dynamic> j, String key, int index, String owner) {
  final v = j[key];
  if (v is! Map<String, dynamic>) {
    throw TemplateManifestFormatException(
      'template "$owner": missing required object "$key"',
    );
  }
  return v;
}
