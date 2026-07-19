import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Geometry helpers for editor annotations.
class AnnotationBoundsService {
  const AnnotationBoundsService();

  /// Normalized bounding box of any annotation.
  Rect boundsOf(EditorAnnotation a) {
    if (a is ShapeAnnotation) return Rect.fromPoints(a.start, a.end);
    if (a is TextAnnotation) {
      final w = (a.text.length * a.size * 0.55).clamp(0.02, 1.0);
      return Rect.fromLTWH(a.pos.dx, a.pos.dy, w.toDouble(), a.size * 1.3);
    }
    if (a is StrokeAnnotation) {
      var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
      for (final p in a.points) {
        minX = math.min(minX, p.dx);
        minY = math.min(minY, p.dy);
        maxX = math.max(maxX, p.dx);
        maxY = math.max(maxY, p.dy);
      }
      return Rect.fromLTRB(minX, minY, maxX, maxY);
    }
    return Rect.zero;
  }
}
