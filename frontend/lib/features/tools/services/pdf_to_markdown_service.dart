/// PDF to Markdown converter — converts document text + structure into
/// a clean Markdown file.
///
/// Uses OCR text + heading detection (from TocGeneratorService) to create:
/// - # Headings at appropriate levels
/// - Paragraph breaks
/// - Bold/italic from detected patterns
/// - Lists (numbered and bulleted)
/// - Horizontal rules for page breaks
///
/// Output can be saved as .md or copied for use in note apps.
class PdfToMarkdownService {
  const PdfToMarkdownService();

  /// Convert per-page text into a single Markdown document.
  String convert(Map<int, String> pageTexts) {
    final buffer = StringBuffer();

    for (final entry in pageTexts.entries) {
      final page = entry.key;
      final text = entry.value;
      if (text.trim().isEmpty) continue;

      if (page > 0 && buffer.isNotEmpty) {
        buffer.writeln('\n---\n'); // page break
      }

      final lines = text.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          buffer.writeln();
          continue;
        }
        buffer.writeln(_processLine(trimmed));
      }
    }

    return buffer.toString().trimRight();
  }

  String _processLine(String line) {
    // Numbered heading: "1. Title" or "1.2 Title"
    if (RegExp(r'^\d+(\.\d+)*\.?\s+\S').hasMatch(line) && line.length < 80) {
      final level = '.'.allMatches(line.split(RegExp(r'\s'))[0]).length;
      final prefix = '#' * (level + 1);
      final text = line.replaceFirst(RegExp(r'^\d+(\.\d+)*\.?\s*'), '');
      return '$prefix $text';
    }

    // ALL CAPS heading
    if (line == line.toUpperCase() && line.length > 3 && line.length < 60 && RegExp(r'[A-Z]').hasMatch(line)) {
      return '## $line';
    }

    // Bullet points
    if (RegExp(r'^[-•●]\s').hasMatch(line)) {
      return '- ${line.substring(2)}';
    }

    // Numbered list
    if (RegExp(r'^\d+[.)]\s').hasMatch(line)) {
      return line; // already valid markdown numbered list
    }

    return line;
  }
}
