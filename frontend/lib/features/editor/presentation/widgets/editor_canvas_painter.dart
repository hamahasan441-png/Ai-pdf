import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/annotation_draw.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// On-screen painter for freehand strokes, shapes, and live previews.
/// Text boxes are drawn as draggable widgets, not here.
class EditorCanvasPainter extends CustomPainter {
  final List<StrokeAnnotation> strokes;
  final List<ShapeAnnotation> shapes;
  final List<Offset> current;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final ShapeType? shapeType;
  final Color curColor;
  final double curWidth;
  final bool curHighlight;

  EditorCanvasPainter(
    this.strokes,
    this.shapes,
    this.current,
    this.shapeStart,
    this.shapeEnd,
    this.shapeType,
    this.curColor,
    this.curWidth,
    this.curHighlight,
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      AnnotationDraw.stroke(canvas, size, s.points, s.color, s.width);
    }
    for (final s in shapes) {
      AnnotationDraw.shape(
          canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
    }
    if (current.length > 1) {
      AnnotationDraw.stroke(
        canvas,
        size,
        current,
        // withOpacity() is deprecated in Flutter 3.27+; use withValues(alpha:)
        curHighlight ? curColor.withValues(alpha: 0.35) : curColor,
        curHighlight ? 16 : curWidth,
      );
    }
    if (shapeType != null && shapeStart != null && shapeEnd != null) {
      AnnotationDraw.shape(
          canvas, size, shapeType!, shapeStart!, shapeEnd!, curColor, curWidth);
    }
  }

  /// Use structural equality so Flutter only repaints when the visible content
  /// actually changes. Returning `true` unconditionally caused the canvas to
  /// repaint on every frame — even during scroll, zoom, and unrelated state
  /// updates — wasting GPU budget and hurting 60 FPS targets.
  @override
  bool shouldRepaint(covariant EditorCanvasPainter old) {
    if (old.curColor != curColor ||
        old.curWidth != curWidth ||
        old.curHighlight != curHighlight ||
        old.shapeStart != shapeStart ||
        old.shapeEnd != shapeEnd ||
        old.shapeType != shapeType ||
        old.current.length != current.length ||
        old.strokes.length != strokes.length ||
        old.shapes.length != shapes.length) {
      return true;
    }
    return false;
  }
}
