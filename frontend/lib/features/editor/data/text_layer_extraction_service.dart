import 'dart:ui' show Color, Offset, Rect;

/// Where a positioned text box came from.
///
/// Native PDF text and OCR are not the same evidence. Callers must not treat
/// an OCR box as an exact content-stream glyph.
enum TextGeometrySource {
  /// Parsed from PDF text operators / font resources.
  native,

  /// Recognized from a page image. Positions and text can be wrong.
  ocr,

  /// Box or style was inferred (for example a missing font size).
  estimated,

  /// The selection contains more than one of the sources above.
  mixed,
}

/// Represents a text element extracted from the PDF's native text layer.
///
/// Unlike OCR-detected text (which operates on the rasterized image), native
/// elements come from the PDF's text content stream. [source] says which one
/// this box actually is.
class PdfTextElement {
  final String text;
  final Rect rect; // normalised 0..1 page coordinates
  final double fontSize; // in pt (from the PDF content stream); 0 if unknown
  final String? fontName;
  final bool isBold;
  final bool isItalic;
  final TextGeometrySource source;

  /// Fill colour the glyphs were painted with, when the content stream sets
  /// it in a colour space we can read (gray, RGB, CMYK). Null if unknown.
  final Color? color;

  /// 0..1. Native geometry defaults to 1. OCR callers should set a lower value.
  final double confidence;

  const PdfTextElement({
    required this.text,
    required this.rect,
    required this.fontSize,
    this.fontName,
    this.isBold = false,
    this.isItalic = false,
    this.source = TextGeometrySource.native,
    this.color,
    this.confidence = 1,
  });

  /// The same element with its box moved by [quarterTurns] clockwise turns
  /// of the page (as the editor turns pages).
  PdfTextElement turned(int quarterTurns) {
    var r = rect;
    for (var i = 0; i < quarterTurns % 4; i++) {
      // A clockwise turn maps (x, y) to (1 - y, x).
      r = Rect.fromLTRB(1 - r.bottom, r.left, 1 - r.top, r.right);
    }
    return PdfTextElement(
      text: text,
      rect: r,
      fontSize: fontSize,
      fontName: fontName,
      isBold: isBold,
      isItalic: isItalic,
      source: source,
      color: color,
      confidence: confidence,
    );
  }
}

/// Service for extracting the native text layer from a PDF page.
///
/// On device, [PdfContentTextExtractor] fills this model from content streams.
/// [parseFromJson] accepts the same shape from a local parser. A missing
/// `fontSize` stays 0 so style matching can mark the size as an estimate
/// instead of pretending the run is 12 pt.
class TextLayerExtractionService {
  const TextLayerExtractionService();

  /// Parse text elements from a backend or local parser response.
  /// Expected format: list of {text, x, y, w, h, fontSize, fontName, bold, italic, source, confidence}
  List<PdfTextElement> parseFromJson(List<dynamic> items) {
    return items
        .whereType<Map>()
        .map((raw) {
          final j = Map<String, dynamic>.from(raw);
          final sourceName = j['source'] as String?;
          final source = switch (sourceName) {
            'ocr' => TextGeometrySource.ocr,
            'estimated' => TextGeometrySource.estimated,
            _ => TextGeometrySource.native,
          };
          final reported = j['confidence'];
          final confidence = reported is num
              ? reported.toDouble().clamp(0.0, 1.0).toDouble()
              : (source == TextGeometrySource.ocr ? 0.55 : 1.0);
          final sizeRaw = j['fontSize'];
          return PdfTextElement(
            text: j['text'] as String? ?? '',
            rect: Rect.fromLTWH(
              (j['x'] as num?)?.toDouble() ?? 0,
              (j['y'] as num?)?.toDouble() ?? 0,
              (j['w'] as num?)?.toDouble() ?? 0,
              (j['h'] as num?)?.toDouble() ?? 0,
            ),
            fontSize: sizeRaw is num ? sizeRaw.toDouble() : 0,
            fontName: j['fontName'] as String?,
            isBold: j['bold'] as bool? ?? false,
            isItalic: j['italic'] as bool? ?? false,
            source: source,
            confidence: confidence,
          );
        })
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
  ///
  /// This joins the list as given. For reading order and line breaks use
  /// [TextSelectionService.selectAll].
  String allText(List<PdfTextElement> elements) {
    return elements.map((e) => e.text).join(' ');
  }

  /// Find the element at a normalised tap position.
  PdfTextElement? hitTest(List<PdfTextElement> elements, Offset normPos) {
    if (!normPos.dx.isFinite || !normPos.dy.isFinite) return null;
    for (final e in elements.reversed) {
      final rect = e.rect;
      if (!rect.left.isFinite || !rect.top.isFinite) continue;
      if (rect.contains(normPos)) return e;
    }
    return null;
  }
}
