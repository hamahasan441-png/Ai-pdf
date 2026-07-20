import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Shared, resolution-independent drawing used by BOTH the on-screen painter
/// and the off-screen export compositor.
///
/// ### Coordinate system
/// All annotation positions are in normalised 0..1 page coordinates.
/// Font sizes are in PDF points (pt) and scaled to canvas via [_ptScale].
///
/// ### Rendering fidelity
/// The same draw calls are used for screen and export so what you see
/// is exactly what you get in the exported PDF.
class AnnotationDraw {
  AnnotationDraw._();

  static const double _refHeight = 1000.0;

  /// Scale for pt-based font sizes: pt × (canvasHeight / 842pt A4 ref).
  static double _ptScale(Size size) => size.height / 842.0;

  // =========================================================================
  // Stroke
  // =========================================================================

  static void stroke(Canvas canvas, Size size, List<Offset> pts, Color color, double width) {
    if (pts.length < 2) return;
    final k = size.height / _refHeight;
    final paint = Paint()
      ..color = color
      ..strokeWidth = (width * k).clamp(0.5, 60.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts[0].dx * size.width, pts[0].dy * size.height);
    for (var i = 1; i < pts.length; i++) {
      // Catmull–Rom smoothing: blend midpoints for a natural pen feel.
      if (i < pts.length - 1) {
        final mid = Offset(
          (pts[i].dx + pts[i + 1].dx) / 2 * size.width,
          (pts[i].dy + pts[i + 1].dy) / 2 * size.height,
        );
        path.quadraticBezierTo(
          pts[i].dx * size.width,
          pts[i].dy * size.height,
          mid.dx,
          mid.dy,
        );
      } else {
        path.lineTo(pts[i].dx * size.width, pts[i].dy * size.height);
      }
    }
    canvas.drawPath(path, paint);
  }

  // =========================================================================
  // Shape
  // =========================================================================

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
      ..strokeWidth = (width * k).clamp(0.5, 40.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = effColor.withOpacity((effColor.opacity * 0.22).clamp(0.0, 1.0))
      ..style = PaintingStyle.fill;

    switch (type) {
      case ShapeType.rect:
        final r = Rect.fromPoints(p1, p2);
        if (filled) canvas.drawRect(r, fillPaint);
        canvas.drawRect(r, paint);
      case ShapeType.line:
        canvas.drawLine(p1, p2, paint);
      case ShapeType.arrow:
        canvas.drawLine(p1, p2, paint);
        _arrowHead(canvas, p1, p2, paint, k);
      case ShapeType.oval:
        final r = Rect.fromPoints(p1, p2);
        if (filled) canvas.drawOval(r, fillPaint);
        canvas.drawOval(r, paint);
      case ShapeType.whiteout:
        final fill = Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.fill;
        canvas.drawRect(Rect.fromPoints(p1, p2), fill);
        final border = Paint()
          ..color = const Color(0xFFCBD5E1)
          ..strokeWidth = (1.0 * k).clamp(0.3, 2.0)
          ..style = PaintingStyle.stroke;
        canvas.drawRect(Rect.fromPoints(p1, p2), border);
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

  // =========================================================================
  // Text — full RTL / rotation / line-height / char-spacing support
  // =========================================================================

  static void text(Canvas canvas, Size size, TextAnnotation t) {
    if (t.text.isEmpty) return;

    final scale = _ptScale(size);
    final fontSize = (t.size * scale).clamp(4.0, 400.0);
    final maxWidth = t.width != null ? t.width! * scale : size.width * (1.0 - t.pos.dx);

    // Detect RTL if not forced.
    final effectiveDirection =
        t.textDirection ?? _detectDirection(t.text);

    // Build TextPainter with full Unicode BiDi support.
    final style = TextStyle(
      color: t.color.withOpacity(t.opacity),
      fontSize: fontSize,
      fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
      fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
      decoration: t.underline ? TextDecoration.underline : TextDecoration.none,
      decorationColor: t.color,
      fontFamily: t.fontFamily,
      height: t.lineHeight,
      letterSpacing: t.charSpacing * scale,
    );

    final tp = TextPainter(
      text: TextSpan(text: t.text, style: style),
      textDirection: effectiveDirection,
      textAlign: t.textAlign,
      maxLines: t.height != null ? null : null,
    )..layout(maxWidth: maxWidth.clamp(1.0, size.width));

    final ox = t.pos.dx * size.width;
    final oy = t.pos.dy * size.height;

    canvas.save();

    // Background fill
    if (t.backgroundColor != null) {
      final bgRect = Rect.fromLTWH(ox - 2, oy - 2, tp.width + 4, tp.height + 4);
      canvas.drawRect(bgRect, Paint()..color = t.backgroundColor!);
    }

    // Border
    if (t.borderColor != null && t.borderWidth > 0) {
      final k = size.height / _refHeight;
      final borderRect = Rect.fromLTWH(ox - 2, oy - 2, tp.width + 4, tp.height + 4);
      canvas.drawRect(
        borderRect,
        Paint()
          ..color = t.borderColor!
          ..strokeWidth = (t.borderWidth * k).clamp(0.3, 6.0)
          ..style = PaintingStyle.stroke,
      );
    }

    // Rotation
    if (t.rotation != 0) {
      canvas.translate(ox + tp.width / 2, oy + tp.height / 2);
      canvas.rotate(-t.rotation);
      canvas.translate(-(tp.width / 2), -(tp.height / 2));
      tp.paint(canvas, Offset.zero);
    } else {
      tp.paint(canvas, Offset(ox, oy));
    }

    canvas.restore();
  }

  // =========================================================================
  // Image
  // =========================================================================

  static void image(Canvas canvas, Size size, ImageAnnotation img, {ui.Image? cachedImage}) {
    if (cachedImage == null) return;
    final rect = Rect.fromLTWH(
      img.pos.dx * size.width,
      img.pos.dy * size.height,
      img.width * size.width,
      img.height * size.height,
    );
    canvas.save();
    if (img.rotation != 0) {
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(-img.rotation);
      canvas.translate(-rect.width / 2, -rect.height / 2);
      canvas.drawImageRect(
        cachedImage,
        Rect.fromLTWH(0, 0, cachedImage.width.toDouble(), cachedImage.height.toDouble()),
        Rect.fromLTWH(0, 0, rect.width, rect.height),
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      canvas.drawImageRect(
        cachedImage,
        Rect.fromLTWH(0, 0, cachedImage.width.toDouble(), cachedImage.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    canvas.restore();
  }

  // =========================================================================
  // Stamp
  // =========================================================================

  static void stamp(Canvas canvas, Size size, StampAnnotation s) {
    final left = s.pos.dx * size.width;
    final top = s.pos.dy * size.height;
    final w = s.width * size.width;
    final h = s.height * size.height;
    final rect = Rect.fromLTWH(left, top, w, h);

    canvas.save();
    if (s.rotation != 0) {
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(-s.rotation);
      canvas.translate(-w / 2, -h / 2);
    } else {
      canvas.translate(left, top);
    }

    final effectiveOpacity = s.opacity.clamp(0.0, 1.0);
    final border = Paint()
      ..color = s.color.withOpacity(effectiveOpacity)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    final drawRect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(drawRect, const Radius.circular(4)),
      border,
    );

    final tp = TextPainter(
      text: TextSpan(
        text: s.displayText,
        style: TextStyle(
          color: s.color.withOpacity(effectiveOpacity),
          fontSize: (h * 0.38).clamp(8.0, 72.0),
          fontWeight: FontWeight.w800,
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w);

    tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));
    canvas.restore();
  }

  // =========================================================================
  // Form field overlay
  // =========================================================================

  static void formField(Canvas canvas, Size size, FormFieldAnnotation f) {
    final left = f.pos.dx * size.width;
    final top = f.pos.dy * size.height;
    final w = f.width * size.width;
    final h = f.height * size.height;

    final scale = _ptScale(size);
    final isCheckable = f.isCheckable;

    // Background fill
    canvas.drawRect(
      Rect.fromLTWH(left, top, w, h),
      Paint()..color = f.fillColor.withOpacity(f.opacity * 0.6),
    );

    // Border
    canvas.drawRect(
      Rect.fromLTWH(left, top, w, h),
      Paint()
        ..color = f.borderColor.withOpacity(f.opacity)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    if (isCheckable) {
      // Draw checkbox / radio indicator
      if (f.checked) {
        final checkPaint = Paint()
          ..color = f.borderColor.withOpacity(f.opacity)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke;
        if (f.fieldType == FormFieldType.radio) {
          canvas.drawCircle(Offset(left + w / 2, top + h / 2), (w * 0.25).clamp(2.0, 8.0),
              Paint()..color = f.borderColor.withOpacity(f.opacity)..style = PaintingStyle.fill);
        } else {
          final path = Path()
            ..moveTo(left + w * 0.2, top + h * 0.5)
            ..lineTo(left + w * 0.45, top + h * 0.75)
            ..lineTo(left + w * 0.8, top + h * 0.25);
          canvas.drawPath(path, checkPaint);
        }
      }
    } else if (f.value.isNotEmpty) {
      // Text value
      final tp = TextPainter(
        text: TextSpan(
          text: f.value,
          style: TextStyle(
            fontSize: (f.fontSize * scale).clamp(6.0, 40.0),
            color: const Color(0xFF1E293B),
            fontFamily: f.fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w - 4);
      tp.paint(canvas, Offset(left + 2, top + (h - tp.height) / 2));
    }
  }

  // =========================================================================
  // Full layer
  // =========================================================================

  /// Paint an entire [PageLayer] onto [canvas].
  /// [imageCache] maps annotation id → decoded [ui.Image].
  static void layer(
    Canvas canvas,
    Size size,
    PageLayer? layer, {
    Map<String, ui.Image> imageCache = const {},
  }) {
    if (layer == null) return;

    // Sort by zIndex for correct layering.
    final sorted = List<EditorAnnotation>.from(layer.items)
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    for (final a in sorted) {
      if (!a.visible) continue;
      if (a is StrokeAnnotation) {
        stroke(canvas, size, a.points, a.color, a.width);
      } else if (a is ShapeAnnotation) {
        shape(canvas, size, a.shape, a.start, a.end, a.color, a.width, a.filled, a.opacity);
      } else if (a is TextAnnotation) {
        text(canvas, size, a);
      } else if (a is ImageAnnotation) {
        image(canvas, size, a, cachedImage: imageCache[a.id]);
      } else if (a is StampAnnotation) {
        stamp(canvas, size, a);
      } else if (a is FormFieldAnnotation) {
        formField(canvas, size, a);
      }
    }
  }

  // =========================================================================
  // Helpers
  // =========================================================================

  /// Detect text direction using Unicode bidi algorithm heuristic.
  static TextDirection _detectDirection(String text) {
    for (final codeUnit in text.runes) {
      // Arabic, Hebrew, Syriac, Persian, Kurdish ranges.
      if ((codeUnit >= 0x0600 && codeUnit <= 0x06FF) || // Arabic
          (codeUnit >= 0x0590 && codeUnit <= 0x05FF) || // Hebrew
          (codeUnit >= 0x0700 && codeUnit <= 0x074F) || // Syriac
          (codeUnit >= 0xFB00 && codeUnit <= 0xFDFF) || // Arabic pres A
          (codeUnit >= 0xFE70 && codeUnit <= 0xFEFF)) {  // Arabic pres B
        return TextDirection.rtl;
      }
      // If Latin / CJK etc. comes first, it's LTR.
      if (codeUnit > 0x007F) continue; // skip ASCII punctuation/numbers
      if (codeUnit >= 0x0041) return TextDirection.ltr;
    }
    return TextDirection.ltr;
  }
}

// ---------------------------------------------------------------------------
// Async image decoder cache (used by ImageAnnotation renderer)
// ---------------------------------------------------------------------------

/// Decode [bytes] to a [ui.Image] for use in [AnnotationDraw.image].
Future<ui.Image> decodeAnnotationImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}
