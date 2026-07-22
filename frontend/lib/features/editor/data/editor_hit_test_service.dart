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
}
