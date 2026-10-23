import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/domain/services/rtl_detection_service.dart';

/// The result of a text-layer selection gesture.
///
/// Holds the contiguous run of selected elements (in reading order), the
/// concatenated plain text ready for the clipboard, and the normalised
/// highlight rects to paint over the page.
///
/// [source] and [confidence] describe the evidence. A native PDF text layer
/// is not an OCR guess. Mixed selections say so instead of inheriting the
/// first word's provenance.
class TextSelectionResult {
  /// Indices (into the source element list) of the selected elements, in
  /// reading order (not necessarily ascending index order).
  final List<int> indices;

  /// Plain text for copy. Words on one visual line are separated by a space.
  /// A new visual line inserts a newline. RTL lines are ordered right-to-left
  /// so the string is logical reading order, not left-to-right visual order.
  final String text;

  /// Normalised 0..1 highlight rects, one per selected element.
  final List<Rect> rects;

  /// Strongest downgrade among the selected elements.
  final TextGeometrySource source;

  /// Lowest element confidence in the selection. 0 when nothing is selected.
  final double confidence;

  const TextSelectionResult({
    required this.indices,
    required this.text,
    required this.rects,
    this.source = TextGeometrySource.native,
    this.confidence = 1,
  });

  bool get isEmpty => indices.isEmpty;
  bool get isNotEmpty => indices.isNotEmpty;

  static const empty = TextSelectionResult(
    indices: [],
    text: '',
    rects: [],
    confidence: 0,
  );
}

/// Computes a text selection over positioned PDF words from a drag gesture.
///
/// Reading order is derived from geometry: lines are clustered by vertical
/// overlap (not a single fixed page-fraction), words inside an RTL line are
/// ordered right-to-left, and a wide vertical gutter splits columns so a
/// two-column page is not interleaved row by row.
///
/// This selects whole extracted elements. It does not rewrite PDF content
/// streams.
class TextSelectionService {
  const TextSelectionService();

  static const RtlDetectionService _rtl = RtlDetectionService();

  /// Minimum empty vertical gap, in normalised page width, before two bands
  /// are treated as columns. Smaller gaps are word spacing.
  static const double columnGap = 0.08;

  /// Resolve the selection between [start] and [end] over [elements].
  TextSelectionResult selectRange(
    List<PdfTextElement> elements,
    Offset start,
    Offset end,
  ) {
    if (elements.isEmpty) return TextSelectionResult.empty;
    if (!_finitePoint(start) || !_finitePoint(end)) return TextSelectionResult.empty;

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

    return _result(elements, selected);
  }

  /// Select every element (whole-page "select all"), in reading order.
  TextSelectionResult selectAll(List<PdfTextElement> elements) {
    if (elements.isEmpty) return TextSelectionResult.empty;
    return _result(elements, _readingOrder(elements));
  }

  /// True when two boxes sit on one visual line.
  ///
  /// Uses vertical overlap and centre distance relative to the boxes' own
  /// heights, so a tall heading and a body line do not share one tolerance
  /// with a 1.2% page-height constant.
  static bool sameVisualLine(Rect a, Rect b) {
    if (!_finiteRect(a) || !_finiteRect(b)) return false;
    final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    final minH = math.min(a.height, b.height);
    if (minH <= 0.0001) {
      return (a.top - b.top).abs() <= 0.008;
    }
    if (overlap > 0 && overlap / minH >= 0.35) return true;
    final dy = (a.center.dy - b.center.dy).abs();
    final avgH = (a.height + b.height) / 2;
    return dy <= 0.45 * avgH;
  }

  TextSelectionResult _result(List<PdfTextElement> elements, List<int> ordered) {
    return TextSelectionResult(
      indices: ordered,
      text: _joinText(elements, ordered),
      rects: [for (final i in ordered) elements[i].rect],
      source: _sourceOf(elements, ordered),
      confidence: _confidenceOf(elements, ordered),
    );
  }

  int _anchorIndex(List<PdfTextElement> elements, Offset p) {
    for (var i = 0; i < elements.length; i++) {
      final rect = elements[i].rect;
      if (!_finiteRect(rect)) continue;
      if (rect.contains(p)) return i;
    }
    var best = -1;
    var bestDist = double.infinity;
    for (var i = 0; i < elements.length; i++) {
      final rect = elements[i].rect;
      if (!_finiteRect(rect)) continue;
      final c = rect.center;
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
    final usable = <int>[];
    final junk = <int>[];
    for (var i = 0; i < elements.length; i++) {
      if (_finiteRect(elements[i].rect)) {
        usable.add(i);
      } else {
        junk.add(i);
      }
    }
    usable.sort((a, b) => elements[a].rect.top.compareTo(elements[b].rect.top));

    final rows = <List<int>>[];
    for (final i in usable) {
      if (rows.isNotEmpty &&
          sameVisualLine(elements[rows.last.last].rect, elements[i].rect)) {
        rows.last.add(i);
      } else {
        rows.add([i]);
      }
    }

    final columns = _splitColumns(elements, rows);
    final pageRtl = _majorityRtl(elements, usable);
    final orderedRows = <List<int>>[];
    if (columns == null) {
      orderedRows.addAll(rows);
    } else {
      final cols = pageRtl ? columns.reversed.toList() : columns;
      for (final col in cols) {
        orderedRows.addAll(col);
      }
    }

    final out = <int>[];
    for (final row in orderedRows) {
      final rtl = _majorityRtl(elements, row);
      final sorted = [...row]..sort((a, b) {
          final c = elements[a].rect.left.compareTo(elements[b].rect.left);
          return rtl ? -c : c;
        });
      out.addAll(sorted);
    }
    out.addAll(junk);
    return out;
  }

  /// Split [rows] into left and right columns when a clear vertical gutter
  /// runs through the page. Returns null when the text is a single column.
  List<List<List<int>>>? _splitColumns(
    List<PdfTextElement> elements,
    List<List<int>> rows,
  ) {
    final all = [for (final row in rows) ...row];
    if (all.length < 4 || rows.length < 2) return null;
    final byLeft = [...all]
      ..sort((a, b) => elements[a].rect.left.compareTo(elements[b].rect.left));
    var bestGap = 0.0;
    var split = 0.0;
    for (var i = 0; i < byLeft.length - 1; i++) {
      final right = elements[byLeft[i]].rect.right;
      final nextLeft = elements[byLeft[i + 1]].rect.left;
      final gap = nextLeft - right;
      if (gap > bestGap) {
        bestGap = gap;
        split = (right + nextLeft) / 2;
      }
    }
    if (bestGap < columnGap) return null;

    final leftIds = <int>[];
    final rightIds = <int>[];
    for (final i in all) {
      final rect = elements[i].rect;
      if (rect.right <= split + 0.0001) {
        leftIds.add(i);
      } else if (rect.left >= split - 0.0001) {
        rightIds.add(i);
      } else {
        return null;
      }
    }
    if (leftIds.isEmpty || rightIds.isEmpty) return null;

    int rowsTouched(Set<int> ids) {
      var n = 0;
      for (final row in rows) {
        if (row.any(ids.contains)) n++;
      }
      return n;
    }

    final leftSet = leftIds.toSet();
    final rightSet = rightIds.toSet();
    if (rowsTouched(leftSet) < 2 || rowsTouched(rightSet) < 2) return null;

    List<List<int>> side(Set<int> ids) {
      return [
        for (final row in rows)
          if (row.any(ids.contains)) [for (final i in row) if (ids.contains(i)) i],
      ];
    }

    return [side(leftSet), side(rightSet)];
  }

  bool _majorityRtl(List<PdfTextElement> elements, List<int> ids) {
    final buf = StringBuffer();
    for (final i in ids) {
      buf.write(elements[i].text);
    }
    return _rtl.isMajorityRtl(buf.toString());
  }

  String _joinText(List<PdfTextElement> elements, List<int> ordered) {
    final buf = StringBuffer();
    for (var i = 0; i < ordered.length; i++) {
      final e = elements[ordered[i]];
      if (i > 0) {
        final prev = elements[ordered[i - 1]];
        if (sameVisualLine(prev.rect, e.rect)) {
          if (!prev.text.endsWith(' ') && !prev.text.endsWith('\n') && !e.text.startsWith(' ')) {
            buf.write(' ');
          }
        } else {
          buf.write('\n');
        }
      }
      buf.write(e.text);
    }
    return buf.toString();
  }

  TextGeometrySource _sourceOf(List<PdfTextElement> elements, List<int> ordered) {
    if (ordered.isEmpty) return TextGeometrySource.native;
    final kinds = <TextGeometrySource>{
      for (final i in ordered) elements[i].source,
    };
    if (kinds.length == 1) return kinds.single;
    return TextGeometrySource.mixed;
  }

  double _confidenceOf(List<PdfTextElement> elements, List<int> ordered) {
    if (ordered.isEmpty) return 0;
    var minC = 1.0;
    for (final i in ordered) {
      final c = elements[i].confidence;
      if (c.isFinite && c < minC) minC = c;
    }
    return minC;
  }
}

bool _finitePoint(Offset p) => p.dx.isFinite && p.dy.isFinite;

bool _finiteRect(Rect r) =>
    r.left.isFinite &&
    r.top.isFinite &&
    r.width.isFinite &&
    r.height.isFinite &&
    r.width >= 0 &&
    r.height >= 0;
