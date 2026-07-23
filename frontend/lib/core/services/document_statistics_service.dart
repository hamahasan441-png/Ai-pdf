/// Document statistics — word count, character count, page count, file size,
/// estimated reading time, language detection.
///
/// Computed from OCR text on-device. Accessible from the viewer/editor via
/// a "Document Info" panel.
class DocumentStatisticsService {
  const DocumentStatisticsService();

  /// Compute statistics from a document's extracted text.
  DocumentStats compute({
    required String fullText,
    required int pageCount,
    required int fileSizeBytes,
  }) {
    final words = fullText.trim().isEmpty
        ? 0
        : fullText.trim().split(RegExp(r'\s+')).length;
    final chars = fullText.length;
    final charsNoSpace = fullText.replaceAll(RegExp(r'\s'), '').length;
    final sentences = fullText.isEmpty
        ? 0
        : fullText.split(RegExp(r'[.!?؟。]+\s*')).where((s) => s.trim().isNotEmpty).length;
    final paragraphs = fullText.isEmpty
        ? 0
        : fullText.split(RegExp(r'\n\s*\n')).where((p) => p.trim().isNotEmpty).length;

    // Average reading speed: 200 wpm for general text.
    final readingTimeMinutes = words > 0 ? (words / 200.0).ceil() : 0;

    return DocumentStats(
      pageCount: pageCount,
      wordCount: words,
      characterCount: chars,
      characterCountNoSpaces: charsNoSpace,
      sentenceCount: sentences,
      paragraphCount: paragraphs,
      fileSizeBytes: fileSizeBytes,
      estimatedReadingMinutes: readingTimeMinutes,
      detectedLanguage: _detectLanguage(fullText),
    );
  }

  /// Simple first-strong-character language detection.
  String _detectLanguage(String text) {
    for (final cp in text.runes) {
      if (cp >= 0x0600 && cp <= 0x06FF) return 'Arabic/Kurdish';
      if (cp >= 0x0590 && cp <= 0x05FF) return 'Hebrew';
      if (cp >= 0x4E00 && cp <= 0x9FFF) return 'Chinese';
      if (cp >= 0x3040 && cp <= 0x30FF) return 'Japanese';
      if (cp >= 0xAC00 && cp <= 0xD7AF) return 'Korean';
      if (cp >= 0x0400 && cp <= 0x04FF) return 'Cyrillic';
      if (cp >= 0x0041 && cp <= 0x007A) return 'Latin';
    }
    return 'Unknown';
  }
}

/// Aggregated document statistics.
class DocumentStats {
  final int pageCount;
  final int wordCount;
  final int characterCount;
  final int characterCountNoSpaces;
  final int sentenceCount;
  final int paragraphCount;
  final int fileSizeBytes;
  final int estimatedReadingMinutes;
  final String detectedLanguage;

  const DocumentStats({
    required this.pageCount,
    required this.wordCount,
    required this.characterCount,
    required this.characterCountNoSpaces,
    required this.sentenceCount,
    required this.paragraphCount,
    required this.fileSizeBytes,
    required this.estimatedReadingMinutes,
    required this.detectedLanguage,
  });

  /// Human-readable file size.
  String get fileSizeFormatted {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
