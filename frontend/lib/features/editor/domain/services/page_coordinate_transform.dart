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

  /// Convert a canvas-pixel rect to normalised 0..1 rect.
  Rect canvasRectToPdf(Rect canvasRect) {
    if (canvasSize.width == 0 || canvasSize.height == 0) return Rect.zero;
    return Rect.fromLTWH(
      canvasRect.left / canvasSize.width,
      canvasRect.top / canvasSize.height,
      canvasRect.width / canvasSize.width,
      canvasRect.height / canvasSize.height,
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
    final tl = _transformPoint(canvasRect.topLeft) + viewportOffset;
    final br = _transformPoint(canvasRect.bottomRight) + viewportOffset;
    return Rect.fromPoints(tl, br);
  }

  /// Apply the zoom matrix to a point (handles translation + scale).
  Offset _transformPoint(Offset point) {
    final m = zoomMatrix;
    // Matrix4 storage: column-major. For a 2D affine:
    // [0]=scaleX, [4]=0, [12]=translateX
    // [1]=0, [5]=scaleY, [13]=translateY
    final storage = m.storage;
    return Offset(
      point.dx * storage[0] + storage[12],
      point.dy * storage[5] + storage[13],
    );
  }

  /// Inverse-transform: screen → canvas (undo zoom/pan).
  Offset _inverseTransformPoint(Offset point) {
    final storage = zoomMatrix.storage;
    final scaleX = storage[0];
    final scaleY = storage[5];
    if (scaleX == 0 || scaleY == 0) return point;
    return Offset(
      (point.dx - storage[12]) / scaleX,
      (point.dy - storage[13]) / scaleY,
    );
  }
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
