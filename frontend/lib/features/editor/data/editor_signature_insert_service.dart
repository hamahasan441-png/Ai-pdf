import 'dart:ui' show Offset, Color;

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Builds a movable + resizable [StrokeAnnotation] from raw signature-pad
/// points.
///
/// The signature is normalised so its bounding box has a sensible default size
/// (aspect-ratio preserved) and is centred on the page. Because the result is a
/// plain [StrokeAnnotation], it flows through the same selection / move / resize
/// machinery as every other annotation — the caller just needs to select it
/// after insertion (set it as the current selection and switch to the pan tool).
class EditorSignatureInsertService {
  const EditorSignatureInsertService();

  /// Convert raw pad [points] into a normalised page-space signature stroke.
  ///
  /// [targetW] is the default width of the signature as a fraction of the page
  /// width (the height follows from the drawing's aspect ratio). [centerX] /
  /// [centerY] are the normalised page coordinates the signature is centred on
  /// (default: middle of the page). The user can drag/resize it afterwards.
  StrokeAnnotation signatureFromPadPoints(
    List<Offset> points, {
    double targetW = 0.32,
    double centerX = 0.5,
    double centerY = 0.5,
  }) {
    const color = Color(0xFF000000);
    const strokeWidth = 2.5;

    if (points.isEmpty) {
      return StrokeAnnotation(const [], color, strokeWidth, false);
    }

    // Bounding box of the raw pad drawing.
    double minX = points.first.dx, maxX = minX;
    double minY = points.first.dy, maxY = minY;
    for (final p in points) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final w = (maxX - minX).abs();
    final h = (maxY - minY).abs();

    // Preserve aspect ratio; clamp height so tall scribbles stay reasonable.
    final aspect = w < 1e-6 ? 0.4 : (h / w);
    final targetH = (targetW * aspect).clamp(0.03, 0.30).toDouble();

    // Place the bounding box centred on (centerX, centerY), kept on-page.
    final left = (centerX - targetW / 2).clamp(0.0, (1.0 - targetW).clamp(0.0, 1.0)).toDouble();
    final top = (centerY - targetH / 2).clamp(0.0, (1.0 - targetH).clamp(0.0, 1.0)).toDouble();

    final normalized = points.map((p) {
      final nx = w < 1e-6 ? 0.0 : (p.dx - minX) / w;
      final ny = h < 1e-6 ? 0.0 : (p.dy - minY) / h;
      return Offset(
        (left + nx * targetW).clamp(0.0, 1.0).toDouble(),
        (top + ny * targetH).clamp(0.0, 1.0).toDouble(),
      );
    }).toList();

    return StrokeAnnotation(normalized, color, strokeWidth, false);
  }
}
