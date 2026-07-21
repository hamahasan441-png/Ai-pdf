import 'dart:ui' show Offset, Rect;

/// Represents a text element extracted from the PDF's native text layer.
///
/// Unlike OCR-detected text (which operates on the rasterized image), these
/// come from the PDF's actual text content stream — they are exact, positioned,
/// and don't require OCR. Available only for text-based PDFs (not scanned).
class PdfTextElement {
  final String text;
  final Rect rect; // normalised 0..1 page coordinates
  final double fontSize; // in pt (from the PDF content stream)
  final String? fontName;
  final bool isBold;
  final bool isItalic;

  const PdfTextElement({
    required this.text,
    required this.rect,
    required this.fontSize,
    this.fontName,
    this.isBold = false,
    this.isItalic = false,
  });
}

/// Service for extracting the native text layer from a PDF page.
///
/// This is the foundation for:
/// - Text selection (tap + drag to select real text)
/// - Copy text from PDF
/// - Search within PDF
/// - Accessible text overlay
///
/// ### Architecture
/// The actual extraction requires native PDF parsing (PyMuPDF on the backend,
/// or a platform channel to PDFium on Android). This service defines the
/// contract and data model; the implementation bridges to one of those backends.
///
/// For now, the client can call the backend's existing OCR path or (future)
/// a dedicated `/document-ai/text-layer` endpoint that returns positioned text.
class TextLayerExtractionService {
  const TextLayerExtractionService();

  /// Parse text elements from a backend response.
  /// Expected format: list of {text, x, y, w, h, fontSize, fontName, bold, italic}
  List<PdfTextElement> parseFromJson(List<dynamic> items) {
    return items
        .whereType<Map<String, dynamic>>()
        .map((j) => PdfTextElement(
              text: j['text'] as String? ?? '',
              rect: Rect.fromLTWH(
                (j['x'] as num?)?.toDouble() ?? 0,
                (j['y'] as num?)?.toDouble() ?? 0,
                (j['w'] as num?)?.toDouble() ?? 0,
                (j['h'] as num?)?.toDouble() ?? 0,
              ),
              fontSize: (j['fontSize'] as num?)?.toDouble() ?? 12,
              fontName: j['fontName'] as String?,
              isBold: j['bold'] as bool? ?? false,
              isItalic: j['italic'] as bool? ?? false,
            ))
        .where((e) => e.text.isNotEmpty)
        .toList();
  }

  /// Find text elements that contain [query] (case-insensitive search).
  List<PdfTextElement> search(List<PdfTextElement> elements, String query) {
    if (query.isEmpty) return [];
    final lower = query.toLowerCase();
    return elements.where((e) => e.text.toLowerCase().contains(lower)).toList();
  }

  /// Get all text as a single string (for copy-all / AI context).
  String allText(List<PdfTextElement> elements) {
    return elements.map((e) => e.text).join(' ');
  }

  /// Find the element at a normalised tap position.
  PdfTextElement? hitTest(List<PdfTextElement> elements, Offset normPos) {
    for (final e in elements.reversed) {
      if (e.rect.contains(normPos)) return e;
    }
    return null;
  }
}
