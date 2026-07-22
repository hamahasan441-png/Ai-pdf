import 'dart:ui' show Offset, Rect;

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// The result of a text-layer selection gesture (Phase 13).
///
/// Holds the contiguous run of selected elements (in reading order), the
/// concatenated plain text ready for the clipboard, and the normalised
/// highlight rects to paint over the page.
class TextSelectionResult {
  /// Indices (into the source element list) of the selected elements, ordered.
  final List<int> indices;

  /// Plain text for copy — elements joined, with a newline inserted where the
  /// vertical position jumps to a new line.
  final String text;

  /// Normalised 0..1 highlight rects, one per selected element.
  final List<Rect> rects;

  const TextSelectionResult({
    required this.indices,
    required this.text,
    required this.rects,
  });

  bool get isEmpty => indices.isEmpty;
  bool get isNotEmpty => indices.isNotEmpty;

  static const empty =
      TextSelectionResult(indices: [], text: '', rects: []);
}

/// Computes a text selection over the native PDF text layer from a drag gesture.
///
/// Given a page's positioned [PdfTextElement]s (from
/// [TextLayerExtractionService]) and the drag's start/end points in normalised
/// 0..1 page coordinates, it resolves the two anchor elements (by hit-test, or
/// the nearest element when the point falls in a gap) and selects the
/// contiguous run between them in reading order.
///
/// Reading order is derived from the elements' geometry (top-to-bottom, then
/// left-to-right) rather than trusting the incoming list order, so selection is
/// correct even if extraction returned elements out of visual order.
///
/// Pure Dart + `dart:ui` geometry only — no widgets — so it is unit-testable.
class TextSelectionService {
  const TextSelectionService();

  /// Vertical tolerance (in normalised page height) for treating two elements
  /// as being on the same visual line.
  ///
  /// Declared `static const` (not an instance field) so the class keeps a
  /// zero-arg `const` constructor without a non-static field initializer.
  static const double lineTolerance = 0.012;

  /// Resolve the selection between [start] and [end] over [elements].
  TextSelectionResult selectRange(
    List<PdfTextElement> elements,
    Offset start,
    Offset end,
  ) {
    if (elements.isEmpty) return TextSelectionResult.empty;

    // Reading-order ranking of the original indices.
    final order = _readingOrder(elements);
    final rankOf = <int, int>{};
    for (var r = 0; r < order.length; r++) {
      rankOf[order[r]] = r;
    }

    final startIdx = _anchorIndex(elements, start);
    final endIdx = _anchorIndex(elements, end);
    if (startIdx < 0 || endIdx < 0) return TextSelectionResult.empty;

    var loRank = rankOf[startIdx]!;
    var hiRank = rankOf[endIdx]!;
    if (loRank > hiRank) {
      final t = loRank;
      loRank = hiRank;
      hiRank = t;
    }

    final selected = <int>[];
    for (var r = loRank; r <= hiRank; r++) {
      selected.add(order[r]);
    }

    return TextSelectionResult(
      indices: selected,
      text: _joinText(elements, selected),
      rects: [for (final i in selected) elements[i].rect],
    );
  }

  /// Select every element (whole-page "select all"), in reading order.
  TextSelectionResult selectAll(List<PdfTextElement> elements) {
    if (elements.isEmpty) return TextSelectionResult.empty;
    final order = _readingOrder(elements);
    return TextSelectionResult(
      indices: order,
      text: _joinText(elements, order),
      rects: [for (final i in order) elements[i].rect],
    );
  }

  // --- internals -----------------------------------------------------------

  /// Element index at [p], or the nearest element (by centre distance) when
  /// [p] doesn't land inside any element.
  int _anchorIndex(List<PdfTextElement> elements, Offset p) {
    for (var i = 0; i < elements.length; i++) {
      if (elements[i].rect.contains(p)) return i;
    }
    var best = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < elements.length; i++) {
      final c = elements[i].rect.center;
      final dx = c.dx - p.dx;
      final dy = c.dy - p.dy;
      final d = dx * dx + dy * dy;
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }

  List<int> _readingOrder(List<PdfTextElement> elements) {
    final indices = List<int>.generate(elements.length, (i) => i);
    indices.sort((a, b) {
      final ra = elements[a].rect;
      final rb = elements[b].rect;
      // Same line (within tolerance) => order by x; else by y.
      if ((ra.top - rb.top).abs() <= lineTolerance) {
        return ra.left.compareTo(rb.left);
      }
      return ra.top.compareTo(rb.top);
    });
    return indices;
  }

  String _joinText(List<PdfTextElement> elements, List<int> ordered) {
    final buf = StringBuffer();
    double? prevTop;
    for (var i = 0; i < ordered.length; i++) {
      final e = elements[ordered[i]];
      if (i > 0) {
        final sameLine =
            prevTop != null && (e.rect.top - prevTop).abs() <= lineTolerance;
        buf.write(sameLine ? ' ' : '\n');
      }
      buf.write(e.text);
      prevTop = e.rect.top;
    }
    return buf.toString();
  }
}
