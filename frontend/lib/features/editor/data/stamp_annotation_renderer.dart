import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';

/// Renders [StampAnnotation] objects onto a canvas.
///
/// Stamps render as a bordered rectangle with bold uppercase text centered
/// inside — matching the professional PDF stamp appearance (APPROVED, DRAFT, etc).
class StampAnnotationRenderer {
  const StampAnnotationRenderer();

  /// Paint a stamp onto [canvas] at the annotation's normalised position.
  void paint(Canvas canvas, Size size, StampAnnotation stamp) {
    final left = stamp.pos.dx * size.width;
    final top = stamp.pos.dy * size.height;
    final w = stamp.width * size.width;
    final h = stamp.height * size.height;

    canvas.save();

    if (stamp.rotation != 0) {
      canvas.translate(left + w / 2, top + h / 2);
      canvas.rotate(-stamp.rotation);
      canvas.translate(-w / 2, -h / 2);
    } else {
      canvas.translate(left, top);
    }

    // Border (rounded rect)
    final borderPaint = Paint()
      ..color = stamp.color
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;
    final drawRect = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRRect(
      RRect.fromRectAndRadius(drawRect, const Radius.circular(4)),
      borderPaint,
    );

    // Text (bold, centered)
    final tp = TextPainter(
      text: TextSpan(
        text: stamp.displayText,
        style: TextStyle(
          color: stamp.color,
          fontSize: (h * 0.4).clamp(8.0, 72.0),
          fontWeight: FontWeight.w900,
          letterSpacing: 2.0,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w);

    tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));

    canvas.restore();
  }
}
