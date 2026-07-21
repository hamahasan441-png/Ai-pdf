import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// An image overlay annotation (photo, logo, scanned stamp, etc.).
///
/// Stores the raw image bytes and a normalised bounding box. The renderer
/// decodes and caches the `ui.Image` lazily (not stored here to avoid
/// serialisation complexity and keep this class isolate-sendable).
///
/// ### Coordinate system
/// [pos] is the top-left corner in normalised 0..1 page coordinates.
/// [width] / [height] are normalised fractions of the page dimensions.
/// [rotation] is in radians (0 = upright, positive = counter-clockwise).
class ImageAnnotation extends EditorAnnotation {
  /// Top-left position (normalised 0..1).
  Offset pos;

  /// Width as a fraction of page width (0..1).
  double width;

  /// Height as a fraction of page height (0..1).
  double height;

  /// Raw PNG/JPEG bytes of the image.
  final Uint8List bytes;

  /// Rotation in radians.
  double rotation;

  /// Optional label (e.g. "Logo", "Photo") for accessibility / history panel.
  final String label;

  ImageAnnotation({
    required this.pos,
    required this.width,
    required this.height,
    required this.bytes,
    this.rotation = 0.0,
    this.label = 'Image',
    super.id,
  });

  /// Create a default-positioned image (center of page, auto-sized to 30% width).
  factory ImageAnnotation.centered({
    required Uint8List bytes,
    double aspectRatio = 1.0,
    String label = 'Image',
  }) {
    const w = 0.3;
    final h = w / aspectRatio;
    return ImageAnnotation(
      pos: Offset(0.5 - w / 2, 0.5 - h / 2),
      width: w,
      height: h,
      bytes: bytes,
      label: label,
    );
  }

  @override
  Rect get bounds => Rect.fromLTWH(pos.dx, pos.dy, width, height);

  @override
  void translate(Offset delta) {
    pos = clampOffset01(pos + delta);
  }

  @override
  void scaleTo(Rect next) {
    pos = Offset(next.left.clamp(0.0, 1.0), next.top.clamp(0.0, 1.0));
    width = next.width.abs().clamp(0.01, 1.0);
    height = next.height.abs().clamp(0.01, 1.0);
  }

  @override
  ImageAnnotation clone({double shift = 0, String? id}) {
    final c = ImageAnnotation(
      pos: Offset(pos.dx + shift, pos.dy + shift),
      width: width,
      height: height,
      bytes: bytes,
      rotation: rotation,
      label: label,
      id: id,
    );
    c.copyBaseFrom(this);
    return c;
  }

  @override
  void restoreFrom(ImageAnnotation o) {
    pos = o.pos;
    width = o.width;
    height = o.height;
    rotation = o.rotation;
    copyBaseFrom(o);
  }
}
