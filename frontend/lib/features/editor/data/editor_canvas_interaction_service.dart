import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';
import 'package:ai_pdf/features/editor/domain/services/annotation_bounds_service.dart';
import 'package:ai_pdf/features/editor/domain/services/ink_smooth_service.dart';

/// Stateless interaction helpers used by the editor canvas gesture handlers.
class EditorCanvasInteractionService {
  final InkSmoothService _ink;

  const EditorCanvasInteractionService({InkSmoothService ink = const InkSmoothService()}) : _ink = ink;

  /// Pointer position on the page as 0..1, clamped to the page.
  ///
  /// Null when there is no usable position: a canvas that is zero-sized or
  /// not finite (during layout or a rotation) or a non-finite pointer. The
  /// caller drops the event instead of storing NaN or infinity in a mark.
  Offset? normalize(Offset local, Size canvas) {
    if (!canvas.width.isFinite || !canvas.height.isFinite || canvas.width <= 0 || canvas.height <= 0) {
      return null;
    }
    if (!local.dx.isFinite || !local.dy.isFinite) return null;
    return Offset(
      (local.dx / canvas.width).clamp(0.0, 1.0),
      (local.dy / canvas.height).clamp(0.0, 1.0),
    );
  }

  ShapeType? shapePreviewType(EditTool tool) {
    switch (tool) {
      case EditTool.line:
        return ShapeType.line;
      case EditTool.arrow:
        return ShapeType.arrow;
      case EditTool.rect:
        return ShapeType.rect;
      case EditTool.oval:
        return ShapeType.oval;
      case EditTool.whiteout:
        return ShapeType.whiteout;
      default:
        return null;
    }
  }

  StrokeAnnotation? completeStroke({
    required List<Offset> drawing,
    required EditTool tool,
    required Color color,
    required double stroke,
  }) {
    if (drawing.length <= 1) return null;
    final points = tool == EditTool.draw ? _ink.smooth(drawing) : List<Offset>.of(drawing);
    return StrokeAnnotation(
      points,
      tool == EditTool.highlight ? color.withOpacity(0.35) : color,
      tool == EditTool.highlight ? 16 : stroke,
      tool == EditTool.highlight,
    );
  }

  ShapeAnnotation? completeShape({
    required Offset? shapeStart,
    required Offset? shapeEnd,
    required EditTool tool,
    required Color color,
    required double stroke,
  }) {
    if (shapeStart == null || shapeEnd == null) return null;
    final type = shapePreviewType(tool);
    if (type == null) return null;
    if ((shapeStart - shapeEnd).distance <= 0.01) return null;
    return ShapeAnnotation(type, shapeStart, shapeEnd, color, stroke);
  }

  Set<EditorAnnotation> marqueeSelection({
    required Iterable<EditorAnnotation> items,
    required Offset? marqueeStart,
    required Offset? marqueeEnd,
    required AnnotationBoundsService bounds,
  }) {
    final out = <EditorAnnotation>{};
    if (marqueeStart == null || marqueeEnd == null) return out;
    final r = Rect.fromPoints(marqueeStart, marqueeEnd);
    if (r.width <= 0.01 && r.height <= 0.01) return out;
    for (final a in items) {
      // Like a tap, a box selection never picks hidden or locked marks.
      if (!a.visible || a.locked) continue;
      if (bounds.boundsOf(a).overlaps(r)) out.add(a);
    }
    return out;
  }
}
