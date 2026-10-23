import 'package:flutter/widgets.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Hit-testing helpers for editor annotations.
class EditorHitTestService {
  const EditorHitTestService();

  /// Tolerances in normalised page units, so a finger can hit thin marks.
  static const double lineSlop = 0.02;
  static const double boxSlop = 0.01;

  /// The topmost visible, unlocked annotation under [n].
  ///
  /// Lines, arrows and ink are hit only near their path. Their bounding box
  /// would also cover the empty area around a diagonal line and take taps
  /// meant for marks underneath. Text is hit inside its box; it used to be
  /// hit only near its top-left anchor, so the end of a word could not be
  /// selected.
  EditorAnnotation? hitTest(PageLayer layer, Offset n) {
    if (!n.dx.isFinite || !n.dy.isFinite) return null;
    for (final item in layer.items.reversed) {
      if (!item.visible || item.locked) continue;
      if (_hits(item, n)) return item;
    }
    return null;
  }

  bool _hits(EditorAnnotation item, Offset n) {
    if (item is ShapeAnnotation) {
      if (item.type == ShapeType.line || item.type == ShapeType.arrow) {
        return _distanceToSegment(n, item.start, item.end) <= lineSlop;
      }
      return item.bounds.inflate(lineSlop).contains(n);
    }
    if (item is StrokeAnnotation) {
      return _nearPolyline(item.points, n, lineSlop, item.breaks);
    }
    // Text, images, stamps, notes, markup and form fields use their box.
    return item.bounds.inflate(boxSlop).contains(n);
  }

  /// Topmost unlocked ink stroke near [n]. The eraser uses this so it removes
  /// a drawing, not the last annotation of any kind.
  StrokeAnnotation? strokeNear(PageLayer layer, Offset n, {double slop = 0.02}) {
    for (final item in layer.items.reversed) {
      if (item is! StrokeAnnotation || !item.visible || item.locked) continue;
      if (_nearPolyline(item.points, n, slop, item.breaks)) return item;
    }
    return null;
  }

  bool _nearPolyline(List<Offset> points, Offset n, double slop, [List<int> breaks = const []]) {
    if (points.isEmpty) return false;
    if (points.length == 1) return (points.first - n).distance <= slop;
    for (var i = 1; i < points.length; i++) {
      if (breaks.contains(i)) {
        if ((points[i] - n).distance <= slop) return true;
        continue;
      }
      if (_distanceToSegment(n, points[i - 1], points[i]) <= slop) return true;
    }
    return false;
  }

  double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return (p - a).distance;
    final t = (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / len2).clamp(0.0, 1.0);
    final closest = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
    return (p - closest).distance;
  }
}
