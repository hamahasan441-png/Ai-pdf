import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Hit-testing helpers for editor annotations.
class EditorHitTestService {
  const EditorHitTestService();

  /// Hit-test in reverse draw order (topmost first): text, shapes, strokes.
  EditorAnnotation? hitTest(PageLayer layer, Offset n) {
    for (final item in layer.items.reversed) {
      if (!item.visible || item.locked) continue;
      if (item is TextAnnotation) {
        if ((item.pos - n).distance < 0.07) return item;
      } else if (item is ShapeAnnotation) {
        final r = Rect.fromPoints(item.start, item.end).inflate(0.03);
        if (r.contains(n)) return item;
      } else if (item is StrokeAnnotation) {
        var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
        for (final p in item.points) {
          minX = math.min(minX, p.dx);
          minY = math.min(minY, p.dy);
          maxX = math.max(maxX, p.dx);
          maxY = math.max(maxY, p.dy);
        }
        final r = Rect.fromLTRB(minX, minY, maxX, maxY).inflate(0.02);
        if (r.contains(n)) return item;
      } else {
        // Box-based objects (image, stamp, form field): use the unified
        // Transformable bounds so every current and future object type is
        // selectable without a bespoke branch.
        if (item.bounds.inflate(0.01).contains(n)) return item;
      }
    }
    return null;
  }

  /// Topmost unlocked ink stroke near [n]. The eraser uses this so it removes
  /// a drawing, not the last annotation of any kind.
  StrokeAnnotation? strokeNear(PageLayer layer, Offset n, {double slop = 0.02}) {
    for (final item in layer.items.reversed) {
      if (item is! StrokeAnnotation || !item.visible || item.locked) continue;
      if (_nearPolyline(item.points, n, slop)) return item;
    }
    return null;
  }

  bool _nearPolyline(List<Offset> points, Offset n, double slop) {
    if (points.isEmpty) return false;
    if (points.length == 1) return (points.first - n).distance <= slop;
    for (var i = 1; i < points.length; i++) {
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
