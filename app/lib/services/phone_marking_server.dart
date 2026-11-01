import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:highlight_creator/data/l10n.dart';
import 'package:highlight_creator/domain/entities/video_source.dart';
import 'package:highlight_creator/services/error_logger.dart';
import 'package:highlight_creator/services/proxy_cache.dart';

/// LAN server behind "手机打点" (see docs/phone_marking.md).
///
/// Steps 1 and 2: token check, the marking page, `/api/sources` with live proxy
/// state, and `/media/<id>` serving the 720p proxy with Range support. The
/// transcodes themselves are queued in [ProxyCache], one ffmpeg at a time.
/// Slot write-back is step 3 and is not here yet.
class PhoneMarkingServer {
  PhoneMarkingServer({
    required List<VideoSource> Function() sources,
    required AppStrings Function() strings,
    ProxyCache? proxies,
  })  : _sources = sources,
        _strings = strings,
        _proxies = proxies ?? ProxyCache();

  /// Fixed port, so the URL in the QR code stays short and readable.
  static const int port = 17331;

  /// Token alphabet without look-alikes (0/o, 1/l), so a user can retype it.
  static const String _tokenAlphabet = 'abcdefghijkmnpqrstuvwxyz23456789';
  static const int tokenLength = 6;

  final List<VideoSource> Function() _sources;
  final AppStrings Function() _strings;
  final ProxyCache _proxies;

  /// Source paths already handed to the queue during this run, so polling
  /// `/api/sources` cannot re-queue a failed transcode every two seconds.
  final Set<String> _warmed = <String>{};

  HttpServer? _server;
  Future<void>? _starting;
  String _token = '';
  String _host = 'localhost';
  String? _lanAddress;

  bool get isRunning => _server != null;

  /// The current token; empty before [start] and after [stop].
  String get token => _token;

  /// Host shown to the user: the LAN IPv4, or `localhost` when there is none.
  String get host => _host;

  /// The LAN address in use, or null when [host] fell back to localhost.
  String? get lanAddress => _lanAddress;

  /// `http://<host>:<port>/`, or null while stopped.
  String? get baseUrl => isRunning ? 'http://$_host:$port/' : null;

  /// Full page URL including the token, i.e. what the QR code carries.
  String? get url {
    if (!isRunning || _token.isEmpty) return null;
    return 'http://$_host:$port/?t=$_token';
  }

  /// Start listening. Idempotent while already running.
  Future<void> start() {
    if (isRunning) return Future<void>.value();
    return _starting ??= _bind().whenComplete(() => _starting = null);
  }

  Future<void> _bind() async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    try {
      _server = server;
      _proxies.resume();
      _token = _newToken();
      _lanAddress = await localLanAddress();
      _host = _lanAddress ?? 'localhost';
      server.listen(
        _handle,
        onError: (Object error, StackTrace stack) =>
            ErrorLogger.log(error, stack, source: 'phone-marking'),
      );
    } catch (_) {
      await server.close(force: true);
      _server = null;
      _token = '';
      _lanAddress = null;
      _host = 'localhost';
      rethrow;
    }
  }

  /// Close the listener, drop the token and stop the transcode in flight.
  ///
  /// A proxy that is half written stays on disk as `.tmp.mp4` and is restarted
  /// on the next run; the next [start] mints a new token and re-queues.
  Future<void> stop() async {
    final server = _server;
    _server = null;
    _token = '';
    _lanAddress = null;
    _host = 'localhost';
    _warmed.clear();
    await _proxies.shutdown();
    if (server != null) await server.close(force: true);
  }

  /// Best usable LAN IPv4. Loopback (127.*) and link-local (169.254.*) are
  /// skipped; 192.168 > 10 > 172.16–31 > anything else. Null when there is
  /// no LAN interface.
  static Future<String?> localLanAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      String? best;
      var bestScore = -1;
      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          final ip = address.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
          final score = _v4Score(ip);
          if (score > bestScore) {
            best = ip;
            bestScore = score;
          }
        }
      }
      return best;
    } catch (e, st) {
      ErrorLogger.log(e, st, source: 'phone-marking');
      return null;
    }
  }

  /// 3 for 192.168/16, 2 for 10/8, 1 for 172.16/12, 0 otherwise.
  ///
  /// Ranking keeps the real LAN ahead of the 172.* adapters Hyper-V, WSL and
  /// Docker install, which a phone on the Wi-Fi cannot reach.
  static int _v4Score(String ip) {
    if (ip.startsWith('192.168.')) return 3;
    if (ip.startsWith('10.')) return 2;
    if (ip.startsWith('172.')) {
      final second = int.tryParse(ip.split('.').elementAt(1)) ?? 0;
      if (second >= 16 && second <= 31) return 1;
    }
    return 0;
  }

  static String _newToken() {
    final random = Random.secure();
    return String.fromCharCodes(List<int>.generate(
      tokenLength,
      (_) => _tokenAlphabet.codeUnitAt(random.nextInt(_tokenAlphabet.length)),
    ));
  }

  /// Constant-time comparison: a wrong token learns nothing from the timing.
  bool _isToken(String? given) {
    if (given == null || _token.isEmpty || given.length != _token.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < _token.length; i++) {
      diff |= given.codeUnitAt(i) ^ _token.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      // Everything, including the page and the API, sits behind the token.
      if (!_isToken(request.uri.queryParameters['t'])) {
        await _empty(response, HttpStatus.forbidden);
        return;
      }
      if (request.method != 'GET') {
        await _empty(response, HttpStatus.notFound);
        return;
      }
      // One snapshot per request: switching projects mid-request cannot make
      // the id lookup and the proxy lookup disagree.
      final sources = _sources();
      final path = request.uri.path;
      if (path == '/') {
        await _send(
          response,
          'text/html; charset=utf-8',
          _page(sources, _strings()),
        );
        return;
      }
      if (path == '/api/sources') {
        await _send(
          response,
          'application/json; charset=utf-8',
          _sourcesJson(sources),
        );
        return;
      }
      if (path.startsWith('/media/')) {
        await _media(sources, request, response);
        return;
      }
      await _empty(response, HttpStatus.notFound);
    } catch (e, st) {
      ErrorLogger.log(e, st, source: 'phone-marking');
      try {
        response.statusCode = HttpStatus.internalServerError;
        await response.close();
      } catch (_) {
        // Client went away; nothing left to answer.
      }
    }
  }

  /// Status only, no body: a wrong token gets 403 and an unknown path 404.
  static Future<void> _empty(HttpResponse response, int status) async {
    response.statusCode = status;
    response.contentLength = 0;
    await response.close();
  }

  static Future<void> _send(
    HttpResponse response,
    String contentType,
    String body,
  ) async {
    response.headers.contentType = ContentType.parse(contentType);
    // The page and the source list change while the dialog is open.
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.write(body);
    await response.close();
  }

  /// Queue every source that has no proxy yet, once per server run.
  ///
  /// This is what makes the first open of a source slow but self-healing: the
  /// page shows the progress `/api/sources` reports and plays the file the
  /// moment it is ready.
  void _warmProxies(List<VideoSource> sources) {
    for (final source in sources) {
      if (!_warmed.add(source.filePath)) continue;
      _proxies.ensureQueued(source.filePath, durationMs: source.durationMs);
    }
  }

  String _sourcesJson(List<VideoSource> sources) {
    _warmProxies(sources);
    final rows = <Map<String, Object?>>[];
    for (final source in sources) {
      final entry = _proxies.entryFor(source.filePath);
      rows.add({
        'id': source.id,
        'name': _baseName(source.filePath),
        'durationMs': source.durationMs,
        'proxy': entry.state.name,
        'progress': entry.progress,
      });
    }
    return jsonEncode(rows);
  }

  /// Serve one proxy file, with Range support (the browser needs it to seek).
  ///
  /// [id] is resolved against the open project's sources and the file path is
  /// derived from that source, so neither the id nor a request header can name
  /// an arbitrary file. A proxy that is not ready is 409 with no body; the page
  /// keeps polling `/api/sources` and starts playing when it flips to ready.
  Future<void> _media(
    List<VideoSource> sources,
    HttpRequest request,
    HttpResponse response,
  ) async {
    _warmProxies(sources);
    late final String id;
    try {
      id = Uri.decodeComponent(request.uri.path.substring('/media/'.length));
    } catch (_) {
      // A malformed escape is a bad request, not a file name.
      await _empty(response, HttpStatus.badRequest);
      return;
    }
    VideoSource? source;
    for (final candidate in sources) {
      if (candidate.id == id) {
        source = candidate;
        break;
      }
    }
    if (source == null) {
      await _empty(response, HttpStatus.notFound);
      return;
    }
    final path = _proxies.readyPath(source.filePath);
    if (path == null) {
      await _empty(response, HttpStatus.conflict);
      return;
    }

    final file = File(path);
    final total = await file.length();
    response.headers.contentType = ContentType('video', 'mp4');
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');

    final range =
        parseRange(request.headers.value(HttpHeaders.rangeHeader), total);
    if (range != null && !range.satisfiable) {
      response.headers
          .set(HttpHeaders.contentRangeHeader, 'bytes */$total');
      await _empty(response, HttpStatus.requestedRangeNotSatisfiable);
      return;
    }
    final start = range?.start ?? 0;
    final end = range?.end ?? total - 1;
    response.statusCode =
        range == null ? HttpStatus.ok : HttpStatus.partialContent;
    response.headers.contentLength = end - start + 1;
    if (range != null) {
      response.headers
          .set(HttpHeaders.contentRangeHeader, 'bytes $start-$end/$total');
    }
    if (total == 0) {
      await response.close();
      return;
    }
    try {
      // pipe() closes the response.
      await file.openRead(start, end + 1).pipe(response);
    } on IOException {
      // The player seeks by aborting the previous response; that is normal and
      // must not land in the error log.
    }
  }

  /// Parse a single `Range: bytes=…` header against a file of [total] bytes.
  ///
  /// Null means "no usable range, send the whole file": absent, malformed, or
  /// multi-range (browsers only send one range for a video element).
  /// `satisfiable: false` means the range starts past EOF and must be a 416.
  static ({int start, int end, bool satisfiable})? parseRange(
    String? header,
    int total,
  ) {
    if (header == null || total <= 0) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;
    final rawStart = match.group(1)!;
    final rawEnd = match.group(2)!;
    if (rawStart.isEmpty && rawEnd.isEmpty) return null;
    if (rawStart.isEmpty) {
      // Suffix form: the last N bytes.
      final suffix = int.tryParse(rawEnd);
      if (suffix == null || suffix <= 0) return null;
      final start = suffix >= total ? 0 : total - suffix;
      return (start: start, end: total - 1, satisfiable: true);
    }
    final start = int.tryParse(rawStart);
    if (start == null) return null;
    if (start >= total) return (start: 0, end: total - 1, satisfiable: false);
    var end = rawEnd.isEmpty ? total - 1 : int.tryParse(rawEnd) ?? total - 1;
    if (end >= total) end = total - 1;
    if (end < start) return null;
    return (start: start, end: end, satisfiable: true);
  }

  String _page(List<VideoSource> sources, AppStrings l10n) {
    final rows = StringBuffer();
    for (final source in sources) {
      final entry = _proxies.entryFor(source.filePath);
      rows.write(
        '<li class="source" data-id="${_escape(source.id)}"'
        ' data-state="${entry.state.name}">'
        '<div class="row">'
        '<span class="name">${_escape(_baseName(source.filePath))}</span>'
        '<span class="duration">${_formatDuration(source.durationMs)}</span>'
        '</div>'
        '<div class="state">${_escape(_stateLabel(l10n, entry))}</div>'
        '<progress max="100" value="${entry.progress}"'
        '${entry.state == ProxyState.ready ? ' hidden' : ''}></progress>'
        '</li>',
      );
    }
    final list = sources.isEmpty
        ? '<p class="empty">${_escape(l10n.phoneMarkingNoSources)}</p>'
        : '<ul>$rows</ul>';
    return '''
<!doctype html>
<html lang="${l10n.code}">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="referrer" content="no-referrer">
<title>${_escape(l10n.phoneMarkingPageTitle)}</title>
<style>
body { margin: 0; padding: 16px; font: 16px/1.4 system-ui, sans-serif; background: #111; color: #eee; }
h1 { font-size: 20px; margin: 0 0 16px; }
h2 { font-size: 14px; color: #aaa; margin: 16px 0 8px; }
[hidden] { display: none !important; }
ul { list-style: none; margin: 0; padding: 0; }
li { display: block; padding: 12px; margin-bottom: 8px; background: #222; border-radius: 8px; cursor: pointer; }
li.selected { outline: 2px solid #6c63ff; }
.row { display: flex; justify-content: space-between; gap: 12px; }
.duration { color: #888; }
.state { margin-top: 6px; font-size: 12px; color: #aaa; }
li[data-state="ready"] .state { color: #4caf50; }
li[data-state="failed"] .state { color: #e57373; }
progress { display: block; width: 100%; height: 6px; margin-top: 6px; accent-color: #6c63ff; }
.empty { color: #888; }
.player { display: grid; place-items: center; height: 180px; margin-top: 16px; padding: 12px; border: 1px dashed #555; border-radius: 8px; color: #888; text-align: center; }
video { width: 100%; margin-top: 16px; background: #000; border-radius: 8px; }
</style>
</head>
<body>
<h1>${_escape(l10n.phoneMarkingPageTitle)}</h1>
<h2>${_escape(l10n.phoneMarkingPageSources)}</h2>
$list
<video id="player" controls playsinline preload="metadata" hidden></video>
<div class="player" id="placeholder">${_escape(l10n.phoneMarkingPagePlayer)}</div>
<script>
(function () {
  var token = new URLSearchParams(location.search).get('t') || '';
  var player = document.getElementById('player');
  var placeholder = document.getElementById('placeholder');
  var rows = Array.prototype.slice.call(document.querySelectorAll('li.source'));
  var preparing = ${_js(l10n.phoneMarkingPagePreparing)};
  var failed = ${_js(l10n.phoneMarkingPageFailed)};
  var pick = ${_js(l10n.phoneMarkingPagePlayer)};
  var selected = null;
  var latest = [];

  function find(id) {
    for (var i = 0; i < latest.length; i++) {
      if (latest[i].id === id) return latest[i];
    }
    return null;
  }

  function mediaUrl(id) {
    return '/media/' + encodeURIComponent(id) + '?t=' + encodeURIComponent(token);
  }

  function paint(row, s) {
    row.dataset.state = s.proxy;
    row.querySelector('.state').textContent = s.proxy === 'ready' ? '\\u2713'
      : s.proxy === 'failed' ? failed
      : preparing + ' ' + s.progress + '%';
    var bar = row.querySelector('progress');
    bar.hidden = s.proxy === 'ready' || s.proxy === 'failed';
    bar.value = s.progress;
  }

  function show(s) {
    if (s.proxy === 'ready') {
      var url = mediaUrl(s.id);
      if (player.dataset.src !== url) {
        player.dataset.src = url;
        player.src = url;
        player.load();
      }
      player.hidden = false;
      placeholder.hidden = true;
    } else {
      player.pause();
      player.hidden = true;
      placeholder.hidden = false;
      placeholder.textContent = s.proxy === 'failed' ? failed
        : preparing + ' ' + s.progress + '%';
    }
  }

  rows.forEach(function (row) {
    row.addEventListener('click', function () {
      selected = row.dataset.id;
      rows.forEach(function (other) {
        other.classList.toggle('selected', other === row);
      });
      var s = find(selected);
      if (s) {
        show(s);
      } else {
        player.hidden = true;
        placeholder.hidden = false;
        placeholder.textContent = pick;
      }
    });
  });

  function apply(list) {
    latest = list;
    rows.forEach(function (row) {
      var s = find(row.dataset.id);
      if (!s) return;
      paint(row, s);
      if (s.id === selected) show(s);
    });
  }

  function poll() {
    fetch('/api/sources?t=' + encodeURIComponent(token), {cache: 'no-store'})
      .then(function (res) { return res.ok ? res.json() : null; })
      .then(function (list) { if (list) apply(list); })
      .catch(function () {})
      .then(function () { setTimeout(poll, 2000); });
  }

  poll();
})();
</script>
</body>
</html>
''';
  }

  static String _stateLabel(AppStrings l10n, ProxyEntry entry) =>
      switch (entry.state) {
        ProxyState.ready => '✓',
        ProxyState.failed => l10n.phoneMarkingPageFailed,
        ProxyState.queued ||
        ProxyState.working =>
          '${l10n.phoneMarkingPagePreparing} ${entry.progress}%',
      };

  /// A Dart string as a JavaScript literal, so quotes cannot break the script.
  static String _js(String value) => jsonEncode(value);

  static String _baseName(String path) => path.split(RegExp(r'[\\/]')).last;

  static String _formatDuration(int milliseconds) {
    final total = milliseconds ~/ 1000;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    String two(int value) => value.toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${two(minutes)}:${two(seconds)}'
        : '${two(minutes)}:${two(seconds)}';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}
