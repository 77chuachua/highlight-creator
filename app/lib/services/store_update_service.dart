import 'dart:io' show Platform, Process;

import 'package:flutter/services.dart';

/// What the Windows runner learned about Microsoft Store updates.
class StoreUpdateInfo {
  /// `available`, `current`, `pending` or `unavailable`.
  final String state;

  /// The newer package's version (`a.b.c.d`) when [state] is `available`.
  final String? version;

  /// Why the check could not run, when [state] is `unavailable`.
  final String? detail;

  const StoreUpdateInfo(this.state, {this.version, this.detail});

  const StoreUpdateInfo.unavailable(String reason)
      : state = 'unavailable',
        version = null,
        detail = reason;

  /// A newer package is waiting in the Store: the only state worth prompting for.
  bool get isAvailable => state == 'available';

  /// The runner is still asking the Store.
  bool get isPending => state == 'pending';

  @override
  String toString() => 'StoreUpdateInfo($state'
      '${version == null ? '' : ' $version'}'
      '${detail == null ? '' : ' — $detail'})';
}

/// Asks the platform whether the Microsoft Store has a newer package for this app.
///
/// Windows never tells a packaged app it is out of date, and the Store's own page
/// shows only "Open" for an app it already considers installed — so the app has to
/// ask, which is what the runner's `highlight_creator/store_update` channel does
/// (Windows.Services.Store.StoreContext). Anything unexpected answers
/// `unavailable`: another platform, an unpackaged dev build, or a package the
/// Store did not install. Callers treat that as "do not prompt".
class StoreUpdateService {
  static const MethodChannel channel =
      MethodChannel('highlight_creator/store_update');

  /// How long to wait for the runner's background check before giving up.
  static const Duration pollInterval = Duration(milliseconds: 1500);
  static const int pollAttempts = 8;

  /// Turn the runner's reply into a result. Pure, so it is testable anywhere.
  static StoreUpdateInfo parse(Object? raw) {
    if (raw is! Map) return const StoreUpdateInfo.unavailable('malformed reply');
    final state = raw['state'];
    if (state is! String || state.isEmpty) {
      return const StoreUpdateInfo.unavailable('malformed reply');
    }
    final version = raw['version'];
    final detail = raw['detail'];
    return StoreUpdateInfo(
      state,
      version: version is String && version.isNotEmpty ? version : null,
      detail: detail is String && detail.isNotEmpty ? detail : null,
    );
  }

  /// One check. Answers `pending` while the runner is still asking the Store.
  ///
  /// No platform gate on purpose: a platform without the channel throws
  /// [MissingPluginException], which reads as `unavailable` — the same answer a
  /// dev build gives.
  static Future<StoreUpdateInfo> check() async {
    try {
      return parse(await channel.invokeMethod<Object?>('check'));
    } on MissingPluginException {
      // A non-Windows build, or a runner predating this channel.
      return const StoreUpdateInfo.unavailable('no platform channel');
    } on PlatformException catch (e) {
      return StoreUpdateInfo.unavailable(e.message ?? e.code);
    }
  }

  /// Polls until the runner has an answer, or gives up.
  ///
  /// The Store call is a network round trip, so the first answer is usually
  /// `pending`; polling keeps the runner free of any need to call back into Dart.
  /// [probe] is a test seam.
  static Future<StoreUpdateInfo> checkWhenReady({
    int attempts = pollAttempts,
    Duration interval = pollInterval,
    Future<StoreUpdateInfo> Function()? probe,
  }) async {
    final check = probe ?? StoreUpdateService.check;
    var info = await check();
    for (var i = 1; i < attempts && info.isPending; i++) {
      await Future<void>.delayed(interval);
      info = await check();
    }
    return info;
  }

  /// Opens the Store's downloads-and-updates page, where the user can install
  /// what the check found.
  static Future<void> openStoreUpdates() async {
    if (!Platform.isWindows) return;
    await Process.run(
      'cmd',
      ['/c', 'start', '', 'ms-windows-store://downloadsandupdates'],
    );
  }
}
