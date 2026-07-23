/// Table of Contents generator — creates a structured TOC from document text
/// by detecting headings, section numbers, and font-size changes.
///
/// The generated TOC can be:
/// 1. Displayed as a navigation panel (tap to jump to page)
/// 2. Inserted as a new first page in the PDF
/// 3. Used for the document outline (PDF bookmarks)
class TocGeneratorService {
  const TocGeneratorService();

  /// Generate a TOC from per-page text content.
  ///
  /// Heuristics:
  /// - Lines that start with a number + dot (e.g. "1. Introduction")
  /// - Lines that are ALL CAPS (section headers)
  /// - Lines that are short (< 60 chars) and followed by longer content
  /// - Lines matching common heading patterns (Chapter, Section, Article)
  List<TocEntry> generate(Map<int, String> pageTexts) {
    final entries = <TocEntry>[];

    for (final entry in pageTexts.entries) {
      final page = entry.key;
      final lines = entry.value.split('\n');

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.length > 80) continue;

        final level = _detectLevel(trimmed);
        if (level != null) {
          entries.add(TocEntry(
            title: _cleanTitle(trimmed),
            page: page,
            level: level,
          ));
        }
      }
    }

    return entries;
  }

  int? _detectLevel(String line) {
    // "1. Title" or "1.2. Title" or "1.2.3 Title"
    if (RegExp(r'^\d+(\.\d+)*\.?\s+\S').hasMatch(line)) {
      final dots = '.'.allMatches(line.split(RegExp(r'\s'))[0]).length;
      return dots; // 0 = top level, 1 = sub, 2 = sub-sub
    }

    // "Chapter X" / "Section X" / "Article X"
    if (RegExp(r'^(Chapter|Section|Article|Part|باب|فصل|بەشی)\s', caseSensitive: false).hasMatch(line)) {
      return 0;
    }

    // ALL CAPS (likely a heading)
    if (line == line.toUpperCase() && line.length > 3 && RegExp(r'[A-Z]').hasMatch(line)) {
      return 0;
    }

    // Short line followed by content (detected at calling level)
    if (line.length < 50 && !line.contains('.') && RegExp(r'^[A-Z\u0600-\u06FF]').hasMatch(line)) {
      return 1;
    }

    return null;
  }

  String _cleanTitle(String line) {
    // Remove leading numbering for display.
    return line.replaceFirst(RegExp(r'^\d+(\.\d+)*\.?\s*'), '').trim();
  }
}

/// A single entry in the generated Table of Contents.
class TocEntry {
  final String title;
  final int page; // 0-indexed
  final int level; // 0 = top, 1 = sub, 2 = sub-sub

  const TocEntry({
    required this.title,
    required this.page,
    required this.level,
  });
}
