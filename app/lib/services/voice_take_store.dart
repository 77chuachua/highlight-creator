import 'dart:convert';
import 'dart:io';

/// One kept audition: the audio that was heard, and the seed that made it.
///
/// The seed is what the user needs to ask for that delivery again (the studio
/// takes one), so it is recorded next to the audio rather than thrown away.
class VoiceTake {
  final String path;

  /// The seed this take was cloned with. Null for takes written before the
  /// seed was recorded, and for clones that ran without one.
  final int? seed;

  const VoiceTake(this.path, {this.seed});
}

/// The last auditioned clone of each narration line, kept for the render.
///
/// Cloning is a dice roll, so auditioning is how the user picks a good one.
/// The take that was just heard is copied aside and the render reuses it
/// instead of rolling again. The signature covers everything the audio was
/// made from, so editing the line (or the pack's tone) still clones afresh.
class VoiceTakeStore {
  VoiceTakeStore(this.dir);

  /// `%TEMP%\5best_narration\takes` (see `top5_dialog.dart`), so it is cleared
  /// with the rest of the narration cache.
  final String dir;

  /// What a take was made from. Compared as one string, so every caller has to
  /// build it through here; [jsonEncode] keeps the fields unambiguous.
  ///
  /// [voice] is the identity of the pack's audio (size + mtime): re-recording a
  /// pack must invalidate its takes even when the pack id did not change.
  static String signature({
    required String packId,
    required String text,
    double speed = 1,
    String instruct = '',
    String promptText = '',
    String voice = '',
  }) =>
      jsonEncode([packId, text, speed, instruct, promptText, voice]);

  /// A slot id becomes a file name: uuids and `week_2026-W43_goal_1` are fine,
  /// but a hand-edited project may carry anything.
  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');

  String _audio(String id) => '$dir${Platform.pathSeparator}${_safe(id)}.wav';
  String _mark(String id) => '$dir${Platform.pathSeparator}${_safe(id)}.sig';

  /// The take for [id] when [signature] still describes it, otherwise null.
  VoiceTake? find(String id, String signature) {
    try {
      final mark = File(_mark(id));
      final audio = File(_audio(id));
      if (!mark.existsSync() || !audio.existsSync()) return null;
      // An interrupted write leaves a stub; serving that is how "the narration
      // is silent" becomes unexplainable. A real take is never this small.
      if (audio.lengthSync() < 1024) return null;
      final raw = mark.readAsStringSync();
      Map<String, Object?>? record;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) record = Map<String, Object?>.from(decoded);
      } catch (_) {
        // A mark from before seeds were recorded: the plain signature.
      }
      if (record == null) {
        return raw == signature ? VoiceTake(audio.path) : null;
      }
      if (record['signature'] != signature) return null;
      final seed = record['seed'];
      return VoiceTake(audio.path, seed: seed is num ? seed.toInt() : null);
    } catch (_) {
      return null;
    }
  }

  /// Keep [audio] as the take for [id]; the next audition replaces it.
  void keep(String id, String signature, String audio, {int? seed}) {
    try {
      final source = File(audio);
      if (!source.existsSync() || source.lengthSync() < 1024) return;
      if (!Directory(dir).existsSync()) {
        Directory(dir).createSync(recursive: true);
      }
      // Through a temp name: an interrupted copy must never be read back as a
      // take that matches its signature.
      final tmp = '${_audio(id)}.tmp';
      source.copySync(tmp);
      File(tmp).renameSync(_audio(id));
      File(_mark(id)).writeAsStringSync(
        jsonEncode({'signature': signature, 'seed': seed}),
      );
    } catch (_) {
      // Not being able to keep a take only costs a re-clone; the audition and
      // the render both still work, so this must not fail the click.
    }
  }
}
