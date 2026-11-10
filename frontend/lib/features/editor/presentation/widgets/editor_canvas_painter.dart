import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/annotation_draw.dart';
import 'package:ai_pdf/features/editor/data/image_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/stamp_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/text_markup_annotation.dart';

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
  final List<TextMarkupAnnotation> markups;
  final List<Rect> markupPreview;
  final TextMarkupKind? markupKind;
  final List<Rect> findRects;
  final int activeFind;
  final List<Rect> wordSelection;
  final bool securePreview;

  /// Bumped by the screen whenever an async image decode completes, so the
  /// canvas repaints even though the annotation list length is unchanged.
  final int revision;

  /// Taken in the constructor. The old painter and the new one share the
  /// same annotation objects, so reading them later would both see the move.
  late final int _captured;

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
    this.markups = const [],
    this.markupPreview = const [],
    this.markupKind,
    this.findRects = const [],
    this.activeFind = -1,
    this.wordSelection = const [],
    this.securePreview = false,
    this.revision = 0,
  }) {
    _captured = _paintSignature();
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final im in images) {
      if (!im.visible) continue;
      imageRenderer.paint(canvas, size, im);
    }
    _paintFind(canvas, size);
    for (final m in markups) {
      if (!m.visible) continue;
      AnnotationDraw.markup(canvas, size, m, multiply: false);
    }
    for (final s in strokes) {
      if (!s.visible) continue;
      final color = s.color.withValues(alpha: (s.color.a * s.opacity).clamp(0.0, 1.0));
      AnnotationDraw.stroke(canvas, size, s.points, color, s.width, s.breaks);
    }
    for (final s in shapes) {
      if (!s.visible) continue;
      if (s.burnsBlackCover) {
        AnnotationDraw.secureCover(canvas, size, s.start, s.end);
      } else {
        AnnotationDraw.shape(
            canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
      }
    }
    for (final st in stamps) {
      if (!st.visible) continue;
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
      if (securePreview) {
        AnnotationDraw.secureCover(canvas, size, shapeStart!, shapeEnd!);
      } else {
        AnnotationDraw.shape(
            canvas, size, shapeType!, shapeStart!, shapeEnd!, curColor, curWidth);
      }
    }
    if (markupKind != null && markupPreview.isNotEmpty) {
      AnnotationDraw.markup(
        canvas,
        size,
        TextMarkupAnnotation(kind: markupKind!, rects: markupPreview, color: curColor),
        multiply: false,
      );
    }
    _paintWordSelection(canvas, size);
  }

  void _paintFind(Canvas canvas, Size size) {
    for (var i = 0; i < findRects.length; i++) {
      final rect = _norm(findRects[i], size);
      final active = i == activeFind;
      canvas.drawRect(
        rect,
        Paint()
          ..color = active ? const Color(0x88FF9800) : const Color(0x55FFEB3B)
          ..style = PaintingStyle.fill,
      );
      if (active) {
        canvas.drawRect(
          rect,
          Paint()
            ..color = const Color(0xFFFF9800)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6,
        );
      }
    }
  }

  void _paintWordSelection(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0x443F51B5);
    final edge = Paint()
      ..color = const Color(0xFF3F51B5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (final r in wordSelection) {
      final rect = _norm(r, size);
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, edge);
    }
  }

  Rect _norm(Rect r, Size size) => Rect.fromLTWH(
        r.left * size.width,
        r.top * size.height,
        r.width * size.width,
        r.height * size.height,
      );

  /// Use structural equality so Flutter only repaints when the visible content
  /// actually changes. Returning `true` unconditionally caused the canvas to
  /// repaint on every frame — even during scroll, zoom, and unrelated state
  /// updates — wasting GPU budget and hurting 60 FPS targets.
  ///
  /// List length is not enough: moving or recolouring a mark keeps the count
  /// and would otherwise leave the old picture on screen.
  @override
  bool shouldRepaint(covariant EditorCanvasPainter old) {
    if (old.curColor != curColor ||
        old.curWidth != curWidth ||
        old.curHighlight != curHighlight ||
        old.shapeStart != shapeStart ||
        old.shapeEnd != shapeEnd ||
        old.shapeType != shapeType ||
        old.current.length != current.length ||
        old.markupKind != markupKind ||
        old.activeFind != activeFind ||
        !_sameRects(old.markupPreview, markupPreview) ||
        !_sameRects(old.findRects, findRects) ||
        !_sameRects(old.wordSelection, wordSelection) ||
        old.securePreview != securePreview ||
        old.revision != revision ||
        old._captured != _captured) {
      return true;
    }
    return false;
  }

  /// Order, place, size and colour of everything this painter draws.
  /// Doubles are quantised so a sub-pixel wobble does not repaint.
  int _paintSignature() {
    var h = 0;
    void mix(Object? value) => h = Object.hash(h, value);
    void q(double value) => mix((value * 10000).round());
    for (final s in strokes) {
      mix(s.id);
      mix(s.visible);
      mix(s.opacity);
      mix(s.color);
      mix(s.width);
      mix(s.highlight);
      mix(s.points.length);
      final b = s.bounds;
      q(b.left);
      q(b.top);
      q(b.right);
      q(b.bottom);
    }
    for (final s in shapes) {
      mix(s.id);
      mix(s.visible);
      mix(s.opacity);
      mix(s.color);
      mix(s.width);
      mix(s.filled);
      mix(s.type);
      q(s.start.dx);
      q(s.start.dy);
      q(s.end.dx);
      q(s.end.dy);
    }
    for (final image in images) {
      mix(image.id);
      mix(image.visible);
      mix(image.opacity);
      q(image.pos.dx);
      q(image.pos.dy);
      q(image.width);
      q(image.height);
      q(image.rotation);
    }
    for (final stamp in stamps) {
      mix(stamp.id);
      mix(stamp.visible);
      mix(stamp.opacity);
      mix(stamp.color);
      mix(stamp.kind);
      mix(stamp.customText);
      q(stamp.pos.dx);
      q(stamp.pos.dy);
      q(stamp.width);
      q(stamp.height);
      q(stamp.rotation);
    }
    mix(_markupSig(markups));
    return h;
  }
}

bool _sameRects(List<Rect> a, List<Rect> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

int _markupSig(List<TextMarkupAnnotation> list) {
  var h = list.length;
  for (final m in list) {
    final b = m.bounds;
    h = Object.hash(h, b.left, b.top, b.right, b.bottom, m.color, m.kind, m.opacity, m.visible);
  }
  return h;
}
