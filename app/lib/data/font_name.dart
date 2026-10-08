import 'dart:io' show File;
import 'dart:typed_data' show ByteData;

/// Extracts the family name from a TTF/OTF/TTC font file by parsing its
/// sfnt `name` table (no external dependencies).
///
/// Returns `null` when the file is missing or the name table can't be read.
String? readFontFamily(String path) {
  final file = File(path);
  if (!file.existsSync()) return null;
  final ByteData data;
  try {
    data = file.readAsBytesSync().buffer.asByteData(0);
  } catch (_) {
    return null;
  }
  return _familyName(data);
}

String? _familyName(ByteData d) {
  if (d.lengthInBytes < 12) return null;

  final sig = _tag(d, 0);
  var numTablesOffset = 4;
  var recordsBase = 12;
  if (sig == 'ttcf') {
    if (d.lengthInBytes < 16) return null;
    final numFonts = d.getUint32(8);
    if (numFonts < 1) return null;
    final fontOffset = d.getUint32(12); // first font's offset table
    numTablesOffset = fontOffset + 4;
    recordsBase = fontOffset + 12;
  }

  if (d.lengthInBytes < numTablesOffset + 2) return null;
  final numTables = d.getUint16(numTablesOffset);

  int? nameOffset;
  for (var i = 0; i < numTables; i++) {
    final rec = recordsBase + i * 16;
    if (rec + 16 > d.lengthInBytes) break;
    if (_tag(d, rec) == 'name') {
      nameOffset = d.getUint32(rec + 8);
      break;
    }
  }
  if (nameOffset == null || nameOffset + 6 > d.lengthInBytes) return null;

  final count = d.getUint16(nameOffset + 2);
  final stringBase = nameOffset + d.getUint16(nameOffset + 4);

  int bestScore = -1;
  String? best;
  for (var i = 0; i < count; i++) {
    final rec = nameOffset + 6 + i * 12;
    if (rec + 12 > d.lengthInBytes) break;
    final platform = d.getUint16(rec);
    final encoding = d.getUint16(rec + 2);
    final language = d.getUint16(rec + 4);
    final nameId = d.getUint16(rec + 6);
    final len = d.getUint16(rec + 8);
    if (nameId != 1 && nameId != 16) continue; // 1 = family, 16 = typographic family
    if (len == 0) continue;
    final strOff = stringBase + d.getUint16(rec + 10);
    if (strOff + len > d.lengthInBytes) continue;

    final String s;
    if (platform == 3) {
      s = _utf16Be(d, strOff, len);
    } else if (platform == 1) {
      s = _latin1(d, strOff, len);
    } else {
      continue;
    }
    if (s.trim().isEmpty) continue;

    final score = (nameId == 16 ? 3 : 2) +
        (platform == 3 ? 1 : 0) +
        (platform == 3 && (encoding == 1 || encoding == 10) ? 1 : 0) +
        (language == 0x0409 || language == 0 ? 1 : 0);
    if (best == null || score > bestScore) {
      bestScore = score;
      best = s.trim();
    }
  }
  return best;
}

String _tag(ByteData d, int offset) {
  if (offset + 4 > d.lengthInBytes) return '';
  final v = d.getUint32(offset);
  return String.fromCharCodes([
    (v >> 24) & 0xFF,
    (v >> 16) & 0xFF,
    (v >> 8) & 0xFF,
    v & 0xFF,
  ]);
}

String _utf16Be(ByteData d, int offset, int length) {
  final units = length ~/ 2;
  final buf = StringBuffer();
  for (var i = 0; i < units; i++) {
    buf.writeCharCode(d.getUint16(offset + i * 2));
  }
  return buf.toString();
}

String _latin1(ByteData d, int offset, int length) {
  final buf = StringBuffer();
  for (var i = 0; i < length; i++) {
    buf.writeCharCode(d.getUint8(offset + i));
  }
  return buf.toString();
}

/// True when the font at [path] claims glyphs for every codepoint in
/// [codePoints] — parsed from its `cmap` table (format 4 for BMP, format 12
/// for non-BMP), the same way [_familyName] reads the `name` table.
///
/// Returns `false` for missing/unreadable files, unparseable tables, or any
/// uncovered codepoint. This is the actual glyph-coverage truth the drawtext
/// pipeline needs: a font that lacks the text's CJK codepoints would render
/// tofu, regardless of its filename.
bool fontHasGlyphs(String path, Iterable<int> codePoints) {
  final cps = codePoints.toSet();
  if (cps.isEmpty) return true;
  final file = File(path);
  if (!file.existsSync()) return false;
  final ByteData data;
  try {
    data = file.readAsBytesSync().buffer.asByteData(0);
  } catch (_) {
    return false;
  }
  try {
    return _cmapCovers(data, cps);
  } catch (_) {
    return false; // malformed table -> treat as not covered
  }
}

bool _cmapCovers(ByteData d, Set<int> cps) {
  if (d.lengthInBytes < 12) return false;
  var numTablesOffset = 4;
  var recordsBase = 12;
  if (_tag(d, 0) == 'ttcf') {
    if (d.lengthInBytes < 16) return false;
    final fontOffset = d.getUint32(12); // first font's offset table
    numTablesOffset = fontOffset + 4;
    recordsBase = fontOffset + 12;
  }
  if (d.lengthInBytes < numTablesOffset + 2) return false;
  final numTables = d.getUint16(numTablesOffset);

  int? cmapOffset;
  for (var i = 0; i < numTables; i++) {
    final rec = recordsBase + i * 16;
    if (rec + 16 > d.lengthInBytes) break;
    if (_tag(d, rec) == 'cmap') {
      cmapOffset = d.getUint32(rec + 8);
      break;
    }
  }
  if (cmapOffset == null || cmapOffset + 4 > d.lengthInBytes) return false;

  final sub = _cmapSubtables(d, cmapOffset);
  final nonBmp = cps.where((c) => c > 0xFFFF).toSet();
  final bmp = cps.difference(nonBmp);
  // Codepoints above the BMP can only be served by a format 12 subtable.
  if (nonBmp.isNotEmpty) {
    final f12 = sub.$2;
    if (f12 == null || !_cmapHasFormat12(d, f12, nonBmp)) return false;
  }
  if (bmp.isNotEmpty) {
    if (sub.$1 != null) {
      if (!_cmapHasFormat4(d, sub.$1!, bmp)) return false;
    } else if (sub.$2 != null) {
      // A format 12 subtable also carries BMP ranges for Unicode fonts.
      if (!_cmapHasFormat12(d, sub.$2!, bmp)) return false;
    } else {
      return false;
    }
  }
  return true;
}

/// Prefer a Windows-Unicode (3,1) or Unicode (0,*) format 4 subtable and a
/// (3,10)/(0,4)/(0,6) format 12 subtable when present.
(int?, int?) _cmapSubtables(ByteData d, int cmap) {
  final numTables = d.getUint16(cmap + 2);
  int? f4;
  int? f12;
  int f4s = -1, f12s = -1;
  for (var i = 0; i < numTables; i++) {
    final rec = cmap + 4 + i * 8;
    if (rec + 8 > d.lengthInBytes) break;
    final platform = d.getUint16(rec);
    final encoding = d.getUint16(rec + 2);
    final off = cmap + d.getUint32(rec + 4);
    if (off + 2 > d.lengthInBytes) continue;
    final fmt = d.getUint16(off);
    final score = (platform == 3 && (encoding == 1 || encoding == 10)) ? 4
        : (platform == 0 && (encoding == 4 || encoding == 6 || encoding == 3)) ? 3
        : (platform == 0) ? 2
        : (platform == 3) ? 1
        : 0;
    if (fmt == 4 && score > f4s) {
      f4s = score;
      f4 = off;
    }
    if (fmt == 12 && score > f12s) {
      f12s = score;
      f12 = off;
    }
  }
  return (f4, f12);
}

/// Format 4 (BMP segment maps): each codepoint is covered when it falls in a
/// segment and maps to a nonzero glyph id.
bool _cmapHasFormat4(ByteData d, int off, Set<int> cps) {
  final segCountX2 = d.getUint16(off + 6);
  final segCount = segCountX2 ~/ 2;
  final endBase = off + 14;
  final startBase = endBase + segCountX2 + 2;
  final deltaBase = startBase + segCount * 2;
  final rangeBase = deltaBase + segCount * 2;
  if (rangeBase + segCount * 2 > d.lengthInBytes) return false;

  for (final cp in cps) {
    if (cp > 0xFFFF) continue;
    var i = -1;
    for (var k = 0; k < segCount; k++) {
      if (cp <= d.getUint16(endBase + k * 2)) {
        i = k;
        break;
      }
    }
    if (i < 0) return false;
    if (cp < d.getUint16(startBase + i * 2)) return false;
    final idRangeOffset = d.getUint16(rangeBase + i * 2);
    if (idRangeOffset == 0) {
      final idDelta = d.getInt16(deltaBase + i * 2);
      if (((cp + idDelta) & 0xFFFF) == 0) return false;
    } else {
      final start = d.getUint16(startBase + i * 2);
      final glyphOff =
          rangeBase + i * 2 + idRangeOffset + (cp - start) * 2;
      if (glyphOff + 2 > d.lengthInBytes) return false;
      if (d.getUint16(glyphOff) == 0) return false;
    }
  }
  return true;
}

/// Format 12 (segmented coverage, full 32-bit range).
bool _cmapHasFormat12(ByteData d, int off, Set<int> cps) {
  final numGroups = d.getUint32(off + 12);
  final base = off + 16;
  if (base + numGroups * 12 > d.lengthInBytes) return false;
  for (final cp in cps) {
    var covered = false;
    for (var g = 0; g < numGroups; g++) {
      final start = d.getUint32(base + g * 12);
      if (cp < start) break; // groups are sorted by start code
      if (cp <= d.getUint32(base + g * 12 + 4)) {
        covered = true;
        break;
      }
    }
    if (!covered) return false;
  }
  return true;
}