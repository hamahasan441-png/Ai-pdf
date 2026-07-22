import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/annotation_draw.dart';
import 'package:ai_pdf/features/editor/data/image_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/stamp_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';

/// On-screen painter for images, freehand strokes, shapes, stamps, and live
/// previews. Text boxes are drawn as draggable widgets, not here.
///
/// Paint order (bottom → top): images, strokes, shapes, stamps. This keeps
/// photos/logos as a background and stamps as an overlay, matching the export
/// compositor so the preview and the exported PDF agree.
class EditorCanvasPainter extends CustomPainter {
  final List<StrokeAnnotation> strokes;
  final List<ShapeAnnotation> shapes;
  final List<ImageAnnotation> images;
  final List<StampAnnotation> stamps;
  final ImageAnnotationRenderer imageRenderer;
  final StampAnnotationRenderer stampRenderer;
  final List<Offset> current;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final ShapeType? shapeType;
  final Color curColor;
  final double curWidth;
  final bool curHighlight;

  /// Bumped by the screen whenever an async image decode completes, so the
  /// canvas repaints even though the annotation list length is unchanged.
  final int revision;

  EditorCanvasPainter(
    this.strokes,
    this.shapes,
    this.images,
    this.stamps,
    this.imageRenderer,
    this.stampRenderer,
    this.current,
    this.shapeStart,
    this.shapeEnd,
    this.shapeType,
    this.curColor,
    this.curWidth,
    this.curHighlight, {
    this.revision = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final im in images) {
      imageRenderer.paint(canvas, size, im);
    }
    for (final s in strokes) {
      AnnotationDraw.stroke(canvas, size, s.points, s.color, s.width);
    }
    for (final s in shapes) {
      AnnotationDraw.shape(
          canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
    }
    for (final st in stamps) {
      stampRenderer.paint(canvas, size, st);
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
        old.shapes.length != shapes.length ||
        old.images.length != images.length ||
        old.stamps.length != stamps.length ||
        old.revision != revision) {
      return true;
    }
    return false;
  }
}
