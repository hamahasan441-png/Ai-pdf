import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/annotation_draw.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// On-screen painter for freehand strokes, shapes, and live previews.
/// Text boxes are drawn as draggable widgets, so they are not painted here.
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
      AnnotationDraw.shape(canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
    }
    if (current.length > 1) {
      AnnotationDraw.stroke(
        canvas,
        size,
        current,
        curHighlight ? curColor.withOpacity(0.35) : curColor,
        curHighlight ? 16 : curWidth,
      );
    }
    if (shapeType != null && shapeStart != null && shapeEnd != null) {
      AnnotationDraw.shape(canvas, size, shapeType!, shapeStart!, shapeEnd!, curColor, curWidth);
    }
  }

  @override
  bool shouldRepaint(covariant EditorCanvasPainter oldDelegate) => true;
}
