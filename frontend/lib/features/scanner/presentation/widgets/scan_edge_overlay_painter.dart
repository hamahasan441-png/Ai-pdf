import 'dart:ui' show Offset;

import 'package:flutter/material.dart';

/// Paints the detected document quad over the camera preview / captured image:
/// a dimmed exterior, an accent border, a rule-of-thirds grid inside, and
/// corner handles. All points are in the widget's local coordinate space.
class ScanEdgeOverlayPainter extends CustomPainter {
  /// Quad corners in widget space, clockwise [TL, TR, BR, BL].
  final List<Offset> corners;

  /// Draw grabbable corner handles (crop mode) vs. a thin live outline.
  final bool showHandles;

  /// Accent colour (e.g. green when auto-detected / confident).
  final Color color;

  ScanEdgeOverlayPainter({
    required this.corners,
    this.showHandles = false,
    this.color = const Color(0xFF00E5A0),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (corners.length != 4) return;

    final path = Path()..addPolygon(corners, true);

    // Dim everything outside the quad.
    final dim = Paint()..color = const Color(0x99000000);
    final outside = Path()
      ..addRect(Offset.zero & size)
      ..addPath(path, Offset.zero)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(outside, dim);

    // Quad border.
    final border = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, border);

    // Rule-of-thirds grid inside the quad (interpolated across edges).
    final grid = Paint()
      ..color = color.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var i = 1; i < 3; i++) {
      final t = i / 3.0;
      // vertical-ish line: interpolate top edge -> bottom edge
      final topPt = Offset.lerp(corners[0], corners[1], t)!;
      final botPt = Offset.lerp(corners[3], corners[2], t)!;
      canvas.drawLine(topPt, botPt, grid);
      // horizontal-ish line: interpolate left edge -> right edge
      final leftPt = Offset.lerp(corners[0], corners[3], t)!;
      final rightPt = Offset.lerp(corners[1], corners[2], t)!;
      canvas.drawLine(leftPt, rightPt, grid);
    }

    if (showHandles) {
      final handleFill = Paint()..color = Colors.white;
      final handleRing = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      for (final c in corners) {
        canvas.drawCircle(c, 10, handleFill);
        canvas.drawCircle(c, 10, handleRing);
      }
    }
  }

  @override
  bool shouldRepaint(ScanEdgeOverlayPainter old) =>
      old.corners != corners ||
      old.showHandles != showHandles ||
      old.color != color;
}
