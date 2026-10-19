import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/editor_text_runs.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/text_markup_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Shared, resolution-independent drawing used by BOTH the on-screen painter
/// and the off-screen export compositor, so the exported PDF looks exactly
/// like what the user sees. Line/arrow/text sizes scale with the canvas height
/// (normalized to a 1000px reference) so a stroke keeps the same relative
/// thickness whether drawn on a phone screen or a 1800px export page.
class AnnotationDraw {
  static const double _refHeight = 1000.0;

  /// Paint a PDF text mark (highlight / underline / strikeout / squiggly).
  /// Highlight uses multiply so the glyphs stay dark, the same way Acrobat
  /// and pdf.js draw a highlight annotation.
  static void markup(
    Canvas canvas,
    Size size,
    TextMarkupAnnotation m, {
    bool multiply = true,
  }) {
    if (!m.visible || m.rects.isEmpty) return;
    final fade = (m.color.a * m.opacity).clamp(0.0, 1.0);
    final color = m.color.withValues(alpha: fade);
    for (final r in m.rects) {
      final rect = Rect.fromLTWH(
        r.left * size.width,
        r.top * size.height,
        r.width * size.width,
        r.height * size.height,
      );
      switch (m.kind) {
        case TextMarkupKind.highlight:
          // Multiply only when the page image is on this same canvas (export).
          // The on-screen painter is a transparent overlay, where multiply
          // would erase the mark.
          final paint = Paint()
            ..color = color.withValues(alpha: multiply ? 0.45 * fade : 0.38)
            ..blendMode = multiply ? BlendMode.multiply : BlendMode.srcOver
            ..style = PaintingStyle.fill;
          canvas.drawRect(rect, paint);
          break;
        case TextMarkupKind.underline:
          final paint = Paint()
            ..color = color
            ..strokeWidth = math.max(1.2, size.height * 0.004)
            ..strokeCap = StrokeCap.round;
          final y = rect.bottom - paint.strokeWidth;
          canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
          break;
        case TextMarkupKind.strikeout:
          final paint = Paint()
            ..color = color
            ..strokeWidth = math.max(1.1, size.height * 0.003)
            ..strokeCap = StrokeCap.round;
          final y = rect.center.dy;
          canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
          break;
        case TextMarkupKind.squiggly:
          final paint = Paint()
            ..color = color
            ..strokeWidth = math.max(1.0, size.height * 0.0025)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round;
          final y = rect.bottom - 1;
          final path = Path()..moveTo(rect.left, y);
          final step = math.max(3.0, rect.height * 0.22);
          var x = rect.left;
          var up = true;
          while (x < rect.right - 0.5) {
            final nx = math.min(x + step, rect.right);
            path.quadraticBezierTo(
              (x + nx) / 2,
              up ? y - step * 0.65 : y + step * 0.3,
              nx,
              y,
            );
            x = nx;
            up = !up;
          }
          canvas.drawPath(path, paint);
          break;
      }
    }
  }

  /// A polyline; each index in [breaks] starts a new stroke.
  static void stroke(Canvas canvas, Size size, List<Offset> pts, Color color, double width,
      [List<int> breaks = const []]) {
    if (pts.length < 2) return;
    final k = size.height / _refHeight;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts[0].dx * size.width, pts[0].dy * size.height);
    for (var i = 1; i < pts.length; i++) {
      if (breaks.contains(i)) {
        path.moveTo(pts[i].dx * size.width, pts[i].dy * size.height);
      } else {
        path.lineTo(pts[i].dx * size.width, pts[i].dy * size.height);
      }
    }
    canvas.drawPath(path, paint);
  }

  static void shape(
    Canvas canvas,
    Size size,
    ShapeType type,
    Offset a,
    Offset b,
    Color color,
    double width, [
    bool filled = false,
    double opacity = 1.0,
  ]) {
    final k = size.height / _refHeight;
    final p1 = Offset(a.dx * size.width, a.dy * size.height);
    final p2 = Offset(b.dx * size.width, b.dy * size.height);
    final effColor = color.withValues(alpha: (color.a * opacity).clamp(0.0, 1.0));
    final paint = Paint()
      ..color = effColor
      ..strokeWidth = width * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = effColor.withValues(alpha: (effColor.a * 0.25).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;

    switch (type) {
      case ShapeType.rect:
        if (filled) canvas.drawRect(Rect.fromPoints(p1, p2), fillPaint);
        canvas.drawRect(Rect.fromPoints(p1, p2), paint);
        break;
      case ShapeType.line:
        canvas.drawLine(p1, p2, paint);
        break;
      case ShapeType.arrow:
        canvas.drawLine(p1, p2, paint);
        _arrowHead(canvas, p1, p2, paint, k);
        break;
      case ShapeType.oval:
        if (filled) canvas.drawOval(Rect.fromPoints(p1, p2), fillPaint);
        canvas.drawOval(Rect.fromPoints(p1, p2), paint);
        break;
      case ShapeType.whiteout:
        final fill = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawRect(Rect.fromPoints(p1, p2), fill);
        final border = Paint()
          ..color = Colors.grey.shade400
          ..strokeWidth = 1 * k
          ..style = PaintingStyle.stroke;
        canvas.drawRect(Rect.fromPoints(p1, p2), border);
        break;
    }
  }

  /// Opaque black cover. Painted into the page raster on export so deleting
  /// a later object cannot reveal the pixels underneath.
  static void secureCover(Canvas canvas, Size size, Offset a, Offset b) {
    canvas.drawRect(
      Rect.fromPoints(
        Offset(a.dx * size.width, a.dy * size.height),
        Offset(b.dx * size.width, b.dy * size.height),
      ),
      Paint()
        ..color = const Color(0xFF000000)
        ..style = PaintingStyle.fill,
    );
  }

  static void _arrowHead(Canvas canvas, Offset from, Offset to, Paint paint, double k) {
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    final headLen = 18.0 * k;
    const headAngle = math.pi / 7;
    final p1 = Offset(
      to.dx - headLen * math.cos(angle - headAngle),
      to.dy - headLen * math.sin(angle - headAngle),
    );
    final p2 = Offset(
      to.dx - headLen * math.cos(angle + headAngle),
      to.dy - headLen * math.sin(angle + headAngle),
    );
    canvas.drawLine(to, p1, paint);
    canvas.drawLine(to, p2, paint);
  }

  static void text(Canvas canvas, Size size, TextAnnotation t) {
    if (t.text.isEmpty) return;
    final tp = AnnotationTextLayout.of(t, size).painter(t);

    final px = t.pos.dx * size.width;
    final py = t.pos.dy * size.height;

    if (t.rotation != 0) {
      canvas.save();
      canvas.translate(px + tp.width / 2, py + tp.height / 2);
      canvas.rotate(-t.rotation);
      canvas.translate(-tp.width / 2, -tp.height / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      tp.paint(canvas, Offset(px, py));
    }
  }

  /// Paint an entire page layer (strokes, shapes, text) onto [canvas].
  static void layer(Canvas canvas, Size size, PageLayer? layer) {
    if (layer == null) return;
    for (final m in layer.items.whereType<TextMarkupAnnotation>()) {
      markup(canvas, size, m);
    }
    for (final s in layer.strokes) {
      stroke(canvas, size, s.points, s.color, s.width, s.breaks);
    }
    for (final s in layer.shapes) {
      shape(canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
    }
    for (final t in layer.texts) {
      text(canvas, size, t);
    }
  }
}
