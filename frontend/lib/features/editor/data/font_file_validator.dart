import 'dart:typed_data';

/// Result of checking bytes before they are treated as a bundled font.
class FontFileCheck {
  final bool ok;
  final String reason;

  const FontFileCheck._(this.ok, this.reason);

  const FontFileCheck.ok() : this._(true, '');

  const FontFileCheck.reject(String reason) : this._(false, reason);
}

/// Which required code points a measured `cmap` did not contain.
///
/// Null from [bmpCoverage] means the table was not read. An empty [missing]
/// list is the only successful coverage result, and only for the code points
/// that were actually checked.
class GlyphCoverage {
  final List<int> missing;
  final int checked;

  const GlyphCoverage({required this.missing, required this.checked});

  bool get complete => missing.isEmpty && checked > 0;
}

/// TrueType sfnt (`0x00010000` or `'true'`), with a `cmap` table.
///
/// Rejects HTML, JSON, empty files, CFF/OTF (`OTTO`), and truncated tables.
/// This does not prove the file is the requested family or that every glyph
/// the document needs is present. Use [bmpCoverage] for that.
FontFileCheck validateTrueType(Uint8List bytes) {
  if (bytes.length < 12) {
    return const FontFileCheck.reject('File is too small to be a TrueType font.');
  }
  final first = bytes[0];
  if (first == 0x3C || first == 0x7B) {
    return const FontFileCheck.reject(
      'File looks like HTML or JSON, not a TrueType font.',
    );
  }
  final version = _u32(bytes, 0);
  if (version == 0x4F54544F) {
    return const FontFileCheck.reject(
      'CFF/OTF (OTTO) is not a TrueType file this exporter can embed.',
    );
  }
  if (version != 0x00010000 && version != 0x74727565) {
    return FontFileCheck.reject(
      'Bad sfnt signature 0x${version.toRadixString(16)}.',
    );
  }
  final numTables = _u16(bytes, 4);
  if (numTables == 0 || numTables > 64) {
    return const FontFileCheck.reject('Font table count is not usable.');
  }
  final directoryEnd = 12 + numTables * 16;
  if (bytes.length < directoryEnd) {
    return const FontFileCheck.reject('Font table directory is truncated.');
  }
  var sawCmap = false;
  for (var i = 0; i < numTables; i++) {
    final record = 12 + i * 16;
    final tag = _u32(bytes, record);
    final offset = _u32(bytes, record + 8);
    final length = _u32(bytes, record + 12);
    if (offset < directoryEnd || length == 0 || offset + length > bytes.length) {
      return const FontFileCheck.reject('A font table points outside the file.');
    }
    if (tag == 0x636D6170) sawCmap = true;
  }
  if (!sawCmap) {
    return const FontFileCheck.reject('TrueType file has no cmap table.');
  }
  return const FontFileCheck.ok();
}

/// Measures Unicode BMP coverage from `cmap` format 4 or 12.
///
/// Returns null when the cmap cannot be read. Does not guess missing glyphs.
GlyphCoverage? bmpCoverage(Uint8List font, Iterable<int> codePoints) {
  final points = codePoints.where((cp) => cp >= 0 && cp <= 0x10FFFF).toList();
  if (points.isEmpty) return null;
  if (!validateTrueType(font).ok) return null;
  final located = _table(font, 0x636D6170);
  if (located == null) return null;
  final cmap = Uint8List.sublistView(
    font,
    located.offset,
    located.offset + located.length,
  );
  final glyphOf = _unicodeGlyphLookup(cmap);
  if (glyphOf == null) return null;
  final missing = <int>[];
  for (final cp in points) {
    final glyph = glyphOf(cp);
    if (glyph == null || glyph == 0) missing.add(cp);
  }
  return GlyphCoverage(missing: missing, checked: points.length);
}

int? Function(int)? _unicodeGlyphLookup(Uint8List cmap) {
  if (cmap.length < 4) return null;
  final numTables = _u16(cmap, 2);
  if (cmap.length < 4 + numTables * 8) return null;
  int? bestOffset;
  var bestScore = -1;
  for (var i = 0; i < numTables; i++) {
    final rec = 4 + i * 8;
    final platform = _u16(cmap, rec);
    final encoding = _u16(cmap, rec + 2);
    final offset = _u32(cmap, rec + 4);
    final score = switch ((platform, encoding)) {
      (3, 1) => 4,
      (3, 10) => 3,
      (0, 4) => 3,
      (0, 3) => 2,
      (0, _) => 1,
      _ => 0,
    };
    if (score > bestScore && offset < cmap.length) {
      bestScore = score;
      bestOffset = offset;
    }
  }
  if (bestOffset == null || bestScore <= 0) return null;
  if (bestOffset + 2 > cmap.length) return null;
  final format = _u16(cmap, bestOffset);
  if (format == 4) return _format4(cmap, bestOffset);
  if (format == 12) return _format12(cmap, bestOffset);
  return null;
}

int? Function(int)? _format4(Uint8List cmap, int start) {
  if (start + 14 > cmap.length) return null;
  final segCount = _u16(cmap, start + 6) ~/ 2;
  if (segCount <= 0) return null;
  final endAt = start + 14;
  final reservedAt = endAt + segCount * 2;
  final startAt = reservedAt + 2;
  final deltaAt = startAt + segCount * 2;
  final offsetAt = deltaAt + segCount * 2;
  final glyphAt = offsetAt + segCount * 2;
  if (glyphAt > cmap.length) return null;
  return (int code) {
    if (code > 0xFFFF) return 0;
    for (var i = 0; i < segCount; i++) {
      final end = _u16(cmap, endAt + i * 2);
      if (code > end) continue;
      final startCode = _u16(cmap, startAt + i * 2);
      if (code < startCode) return 0;
      final delta = _s16(_u16(cmap, deltaAt + i * 2));
      final rangeOffset = _u16(cmap, offsetAt + i * 2);
      if (rangeOffset == 0) return (code + delta) & 0xFFFF;
      final glyphIndexPos = offsetAt + i * 2 + rangeOffset + (code - startCode) * 2;
      if (glyphIndexPos + 1 >= cmap.length) return 0;
      final glyphIndex = _u16(cmap, glyphIndexPos);
      if (glyphIndex == 0) return 0;
      return (glyphIndex + delta) & 0xFFFF;
    }
    return 0;
  };
}

int? Function(int)? _format12(Uint8List cmap, int start) {
  if (start + 16 > cmap.length) return null;
  final groups = _u32(cmap, start + 12);
  if (start + 16 + groups * 12 > cmap.length) return null;
  return (int code) {
    var lo = 0;
    var hi = groups;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final rec = start + 16 + mid * 12;
      final startChar = _u32(cmap, rec);
      final endChar = _u32(cmap, rec + 4);
      if (code < startChar) {
        hi = mid;
      } else if (code > endChar) {
        lo = mid + 1;
      } else {
        final startGlyph = _u32(cmap, rec + 8);
        return startGlyph + (code - startChar);
      }
    }
    return 0;
  };
}

({int offset, int length})? _table(Uint8List font, int tag) {
  final numTables = _u16(font, 4);
  for (var i = 0; i < numTables; i++) {
    final record = 12 + i * 16;
    if (_u32(font, record) != tag) continue;
    return (offset: _u32(font, record + 8), length: _u32(font, record + 12));
  }
  return null;
}

int _u16(Uint8List bytes, int offset) => (bytes[offset] << 8) | bytes[offset + 1];

int _s16(int value) => value >= 0x8000 ? value - 0x10000 : value;

int _u32(Uint8List bytes, int offset) =>
    (bytes[offset] << 24) |
    (bytes[offset + 1] << 16) |
    (bytes[offset + 2] << 8) |
    bytes[offset + 3];
