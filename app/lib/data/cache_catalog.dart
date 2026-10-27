/// Which files under the results folder are Make's leftovers.
///
/// Make re-renders all of these on every run, so once the reel is made they
/// are waste. `final.mp4` is deliberately excluded: that is what Make
/// produces, and you may still want it. The project autosaves (`*.hlcproj`)
/// and everything under `best5` are excluded by construction - this only ever
/// sees the direct children of the results folder.
final RegExp makeIntermediatePattern = RegExp(
    r'^(slot_\d+_(sub|transition)|body|body_music|startup_normalized'
    r'|startup_titled|ending_normalized)\.mp4$');

/// Whether [fileName] is a Make intermediate that is safe to delete.
bool isMakeIntermediate(String fileName) =>
    makeIntermediatePattern.hasMatch(fileName);
