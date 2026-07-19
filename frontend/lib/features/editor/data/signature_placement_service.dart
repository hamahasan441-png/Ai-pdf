import 'dart:ui' show Offset;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Maps signature-pad geometry into normalized editor strokes.
class SignaturePlacementService {
  const SignaturePlacementService();

  /// Position raw signature-pad points with their top-left near (x, y) on the
  /// page, preserving aspect ratio. Returns null if the points have no
  /// meaningful extent.
  StrokeAnnotation? signatureStrokeAt(
    List<Offset> points,
    double x,
    double y, {
    double targetW = 0.26,
  }) {
    if (points.length < 2) return null;
    double minX = points.first.dx, maxX = minX, minY = points.first.dy, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final w = (maxX - minX).abs();
    final h = (maxY - minY).abs();
    if (w < 1e-3 && h < 1e-3) return null;
    final aspect = w == 0 ? 0.4 : (h / w);
    final targetH = (targetW * aspect).clamp(0.02, 0.14).toDouble();
    final top = (y - targetH * 0.6).clamp(0.0, 0.97).toDouble();
    final normalized = points.map((p) {
      final nx = w == 0 ? 0.0 : (p.dx - minX) / w;
      final ny = h == 0 ? 0.0 : (p.dy - minY) / h;
      return Offset(
        (x + nx * targetW).clamp(0.0, 1.0).toDouble(),
        (top + ny * targetH).clamp(0.0, 1.0).toDouble(),
      );
    }).toList();
    return StrokeAnnotation(normalized, Colors.black, 2.5, false);
  }
}
