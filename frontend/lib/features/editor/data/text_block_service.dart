import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/domain/services/rtl_detection_service.dart';
import 'package:ai_pdf/features/editor/domain/services/text_selection_service.dart';

/// A paragraph of the page's own text: its lines, each a list of word
/// indices in reading order, and the box around them.
class TextBlock {
  final List<List<int>> lines;
  final Rect rect;

  /// Distance from one line's top to the next, as a fraction of page height.
  /// 0 for a single line.
  final double linePitch;

  const TextBlock(this.lines, this.rect, this.linePitch);

  List<int> get words => [for (final l in lines) ...l];
}

/// Groups positioned words into lines and lines into paragraphs, the way a
/// reader sees them, so "Edit text" can offer a whole paragraph to edit.
///
/// Rects are normalised to the page (x by width, y by height); [aspect] is
/// page width / height so horizontal gaps can be compared with text height.
class TextBlockService {
  const TextBlockService();

  static const _rtl = RtlDetectionService();

  List<TextBlock> blocks(List<PdfTextElement> words, {double aspect = 1}) {
    final lines = _lines(words, aspect);
    lines.sort((a, b) => a.rect.top.compareTo(b.rect.top));
    final used = List<bool>.filled(lines.length, false);
    final out = <TextBlock>[];
    for (var i = 0; i < lines.length; i++) {
      if (used[i]) continue;
      used[i] = true;
      final group = [lines[i]];
      // Take the nearest following line that continues this paragraph.
      for (var j = i + 1; j < lines.length; j++) {
        if (used[j]) continue;
        final last = group.last;
        final next = lines[j];
        final h = last.rect.height;
        final gap = next.rect.top - last.rect.bottom;
        if (gap > h * 0.9) break;
        if (_continues(last, next, aspect)) {
          used[j] = true;
          group.add(next);
        }
      }
      var rect = group.first.rect;
      for (final l in group.skip(1)) {
        rect = rect.expandToInclude(l.rect);
      }
      final pitch = group.length < 2 ? 0.0 : (group.last.rect.top - group.first.rect.top) / (group.length - 1);
      out.add(TextBlock([for (final l in group) l.words], rect, pitch));
    }
    return out;
  }

  /// Words on one visual line, split where the gap is wide enough to be a
  /// column or table cell boundary, in reading order.
  List<_Line> _lines(List<PdfTextElement> words, double aspect) {
    final order = [
      for (var i = 0; i < words.length; i++)
        if (words[i].text.trim().isNotEmpty && _finite(words[i].rect)) i,
    ]..sort((a, b) => words[a].rect.center.dy.compareTo(words[b].rect.center.dy));
    final rows = <List<int>>[];
    for (final i in order) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null && TextSelectionService.sameVisualLine(words[row.first].rect, words[i].rect)) {
        row.add(i);
      } else {
        rows.add([i]);
      }
    }
    final out = <_Line>[];
    for (final row in rows) {
      row.sort((a, b) => words[a].rect.left.compareTo(words[b].rect.left));
      var seg = <int>[row.first];
      for (final i in row.skip(1)) {
        final prev = words[seg.last].rect;
        final cur = words[i].rect;
        final h = math.max(prev.height, cur.height);
        if ((cur.left - prev.right) * aspect > h * 2.5) {
          out.add(_Line.of(words, seg));
          seg = [i];
        } else {
          seg.add(i);
        }
      }
      out.add(_Line.of(words, seg));
    }
    return out;
  }

  bool _continues(_Line a, _Line b, double aspect) {
    final ha = a.rect.height, hb = b.rect.height;
    if (math.max(ha, hb) / math.max(math.min(ha, hb), 1e-6) > 1.35) return false;
    final overlap = math.min(a.rect.right, b.rect.right) - math.max(a.rect.left, b.rect.left);
    if (overlap <= 0) return false;
    // Same left edge (left-aligned text), same right edge (RTL or justified),
    // or the same centre (centred text).
    final tol = ha / aspect * 1.5;
    return (a.rect.left - b.rect.left).abs() <= tol ||
        (a.rect.right - b.rect.right).abs() <= tol ||
        (a.rect.center.dx - b.rect.center.dx).abs() <= tol;
  }

  static bool _finite(Rect r) => r.left.isFinite && r.top.isFinite && r.right.isFinite && r.bottom.isFinite;
}

class _Line {
  final List<int> words;
  final Rect rect;

  _Line(this.words, this.rect);

  /// [seg] sorted left to right; an RTL line reads right to left.
  factory _Line.of(List<PdfTextElement> all, List<int> seg) {
    var rect = all[seg.first].rect;
    for (final i in seg.skip(1)) {
      rect = rect.expandToInclude(all[i].rect);
    }
    final text = seg.map((i) => all[i].text).join(' ');
    final ordered = TextBlockService._rtl.isRtl(text) ? seg.reversed.toList() : seg;
    return _Line(ordered, rect);
  }
}
