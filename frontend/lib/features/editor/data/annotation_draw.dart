import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/editor_text_runs.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Shared, resolution-independent drawing used by BOTH the on-screen painter
/// and the off-screen export compositor, so the exported PDF looks exactly
/// like what the user sees. Line/arrow/text sizes scale with the canvas height
/// (normalized to a 1000px reference) so a stroke keeps the same relative
/// thickness whether drawn on a phone screen or a 1800px export page.
class AnnotationDraw {
  static const double _refHeight = 1000.0;

  static void stroke(Canvas canvas, Size size, List<Offset> pts, Color color, double width) {
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
      path.lineTo(pts[i].dx * size.width, pts[i].dy * size.height);
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
    final effColor = color.withOpacity((color.opacity * opacity).clamp(0.0, 1.0));
    final paint = Paint()
      ..color = effColor
      ..strokeWidth = width * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = effColor.withOpacity((effColor.opacity * 0.25).clamp(0.0, 1.0))
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
    final base = TextStyle(
      color: t.color,
      fontSize: t.size * size.height,
      // w700/w400 match the exported Helvetica-Bold/Helvetica weights so
      // the preview and the PDF agree (WYSIWYG).
      fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
      decoration: t.underline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: t.color,
      fontFamily: t.fontFamily,
    );
    final tp = TextPainter(
      text: buildAnnotationTextSpan(t, base),
      textDirection: t.textDirection ?? TextDirection.ltr,
    )..layout(maxWidth: size.width * (1 - t.pos.dx));
    tp.paint(canvas, Offset(t.pos.dx * size.width, t.pos.dy * size.height));
  }

  /// Paint an entire page layer (strokes, shapes, text) onto [canvas].
  static void layer(Canvas canvas, Size size, PageLayer? layer) {
    if (layer == null) return;
    for (final s in layer.strokes) {
      stroke(canvas, size, s.points, s.color, s.width);
    }
    for (final s in layer.shapes) {
      shape(canvas, size, s.type, s.start, s.end, s.color, s.width, s.filled, s.opacity);
    }
    for (final t in layer.texts) {
      text(canvas, size, t);
    }
  }
}
