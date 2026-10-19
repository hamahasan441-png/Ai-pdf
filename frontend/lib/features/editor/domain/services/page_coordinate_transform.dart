import 'dart:math' as math;
import 'dart:typed_data' show Float64List;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/widgets.dart' show Matrix4;

/// Converts between normalised PDF coordinates (0..1) and screen pixels.
///
/// ### Why this exists
/// Annotations store positions in normalised 0..1 page coordinates. To overlay
/// a live `TextField` or selection handles on top of the canvas at the exact
/// pixel position, we need a transform that accounts for:
/// - The canvas widget's position on screen (its render-box offset)
/// - The current zoom/pan from `InteractiveViewer` (its `TransformationController.value`)
/// - The page's rendered size within the viewport
///
/// ### Usage (inline text editing, P1)
/// ```dart
/// final transform = PageCoordinateTransform(
///   canvasSize: Size(411, 581),        // from LayoutBuilder
///   viewportOffset: Offset(0, 56),     // canvas global position
///   zoomMatrix: controller.value,      // InteractiveViewer transform
/// );
/// final screenRect = transform.pdfToScreen(Rect.fromLTWH(t.pos.dx, t.pos.dy, w, h));
/// // → position a TextField overlay at screenRect
/// ```
///
/// ### Coordinate systems
/// - **PDF normalised** (0..1): annotation positions, field rects
/// - **Canvas pixels**: the rendered page image's coordinate space
/// - **Screen pixels**: absolute device coordinates (for overlays outside the canvas)
class PageCoordinateTransform {
  /// The size of the canvas widget (page image box) in logical pixels.
  final Size canvasSize;

  /// The global offset of the canvas widget's top-left corner on screen.
  /// Obtain via `RenderBox.localToGlobal(Offset.zero)`.
  final Offset viewportOffset;

  /// The current zoom/pan matrix from `InteractiveViewer.transformationController.value`.
  /// Identity matrix if no zoom/pan has been applied.
  final Matrix4 zoomMatrix;

  const PageCoordinateTransform({
    required this.canvasSize,
    this.viewportOffset = Offset.zero,
    Matrix4? zoomMatrix,
  }) : zoomMatrix = zoomMatrix ?? const _IdentityMatrix();

  /// A point on the fitted page, after the same zoom/pan matrix the
  /// [InteractiveViewer] applies to the whole viewport child.
  ///
  /// The page box is centered in the viewport, then the viewer scales and
  /// translates that entire child. Applying the centering offset before the
  /// matrix keeps an overlay outside the viewer on the same pixels.
  static Offset zoomedPagePoint({
    required Offset norm,
    required double pageLeft,
    required double pageTop,
    required Size pageSize,
    required Matrix4 zoom,
  }) {
    final local = Offset(
      pageLeft + norm.dx * pageSize.width,
      pageTop + norm.dy * pageSize.height,
    );
    return mapPoint(zoom, local);
  }

  /// Uniform scale of a zoom/pan/rotate matrix. `storage[0]` is only the
  /// X component and is 0 for a 90° rotation, which collapsed overlay text.
  static double uniformScale(Matrix4 zoom) {
    final storage = zoom.storage;
    final sx = math.sqrt(storage[0] * storage[0] + storage[1] * storage[1]);
    final sy = math.sqrt(storage[4] * storage[4] + storage[5] * storage[5]);
    if (sx == 0 && sy == 0) return 1;
    if (sx == 0) return sy;
    if (sy == 0) return sx;
    return (sx + sy) / 2;
  }

  /// Full 2D affine map. Uses the off-diagonal terms, not only scale and
  /// translation, so a rotated viewer matrix stays invertible.
  static Offset mapPoint(Matrix4 zoom, Offset point) {
    final s = zoom.storage;
    return Offset(
      s[0] * point.dx + s[4] * point.dy + s[12],
      s[1] * point.dx + s[5] * point.dy + s[13],
    );
  }

  static Offset invertPoint(Matrix4 zoom, Offset point) {
    final s = zoom.storage;
    final a = s[0];
    final b = s[1];
    final c = s[4];
    final d = s[5];
    final tx = s[12];
    final ty = s[13];
    final det = a * d - c * b;
    if (det.abs() < 1e-12) return point;
    final x = point.dx - tx;
    final y = point.dy - ty;
    return Offset((d * x - c * y) / det, (-b * x + a * y) / det);
  }

  // ─── PDF → Canvas ───────────────────────────────────────────────────────

  /// Convert a normalised 0..1 offset to canvas-pixel coordinates.
  Offset pdfToCanvas(Offset norm) {
    return Offset(
      norm.dx * canvasSize.width,
      norm.dy * canvasSize.height,
    );
  }

  /// Convert a normalised 0..1 rect to canvas-pixel rect.
  Rect pdfRectToCanvas(Rect norm) {
    return Rect.fromLTWH(
      norm.left * canvasSize.width,
      norm.top * canvasSize.height,
      norm.width * canvasSize.width,
      norm.height * canvasSize.height,
    );
  }

  // ─── Canvas → PDF ───────────────────────────────────────────────────────

  /// Convert a canvas-pixel offset to normalised 0..1 coordinates.
  Offset canvasToPdf(Offset canvasPixel) {
    if (canvasSize.width == 0 || canvasSize.height == 0) return Offset.zero;
    return Offset(
      canvasPixel.dx / canvasSize.width,
      canvasPixel.dy / canvasSize.height,
    );
  }

  // ─── PDF → Screen (accounts for zoom + viewport offset) ─────────────────

  /// Convert a normalised annotation rect to absolute screen coordinates.
  /// Use this to position overlay widgets (TextField, selection handles) on top
  /// of the canvas at the correct zoomed/panned location.
  Rect pdfToScreen(Rect normRect) {
    final canvasRect = pdfRectToCanvas(normRect);
    return _applyZoomAndOffset(canvasRect);
  }

  /// Convert a normalised annotation offset to absolute screen coordinates.
  Offset pdfOffsetToScreen(Offset norm) {
    final canvasPoint = pdfToCanvas(norm);
    final transformed = _transformPoint(canvasPoint);
    return transformed + viewportOffset;
  }

  // ─── Screen → PDF (reverse: for tap events on overlays) ─────────────────

  /// Convert an absolute screen offset to normalised PDF coordinates.
  /// Use this when a tap/drag event comes from an overlay widget positioned
  /// in screen space and needs to map back to the annotation coordinate system.
  Offset screenToPdf(Offset screen) {
    final local = screen - viewportOffset;
    final canvasPoint = _inverseTransformPoint(local);
    return canvasToPdf(canvasPoint);
  }

  // ─── Internal helpers ───────────────────────────────────────────────────

  Rect _applyZoomAndOffset(Rect canvasRect) {
    final corners = [
      canvasRect.topLeft,
      canvasRect.topRight,
      canvasRect.bottomLeft,
      canvasRect.bottomRight,
    ];
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final corner in corners) {
      final p = _transformPoint(corner) + viewportOffset;
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    if (!minX.isFinite || !minY.isFinite) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Apply the zoom matrix to a point, including rotation and skew.
  Offset _transformPoint(Offset point) => mapPoint(zoomMatrix, point);

  /// Inverse-transform: screen → canvas (undo zoom/pan/rotation).
  Offset _inverseTransformPoint(Offset point) => invertPoint(zoomMatrix, point);
}

/// Placeholder for the identity matrix when none is provided (const-friendly).
class _IdentityMatrix implements Matrix4 {
  const _IdentityMatrix();

  @override
  Float64List get storage => Float64List.fromList([
        1, 0, 0, 0, //
        0, 1, 0, 0, //
        0, 0, 1, 0, //
        0, 0, 0, 1, //
      ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
