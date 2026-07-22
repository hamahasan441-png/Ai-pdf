import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size;

/// The four corners of a detected document, always stored in a canonical
/// clockwise order starting from the top-left: TL, TR, BR, BL.
///
/// Coordinates are in the same space the caller works in — typically the raw
/// pixel space of the captured frame, or the normalised 0..1 preview space.
/// [CornerOrderingService] guarantees the ordering; this class assumes it.
class DocumentCorners {
  final Offset topLeft;
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const DocumentCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// A full-frame quad for [size] (the whole image is the "document").
  factory DocumentCorners.fullFrame(Size size) => DocumentCorners(
        topLeft: Offset.zero,
        topRight: Offset(size.width, 0),
        bottomRight: Offset(size.width, size.height),
        bottomLeft: Offset(0, size.height),
      );

  /// A full-frame quad inset by [margin] (0..0.5 fraction of each dimension).
  factory DocumentCorners.insetFrame(Size size, double margin) {
    final mx = size.width * margin.clamp(0.0, 0.49);
    final my = size.height * margin.clamp(0.0, 0.49);
    return DocumentCorners(
      topLeft: Offset(mx, my),
      topRight: Offset(size.width - mx, my),
      bottomRight: Offset(size.width - mx, size.height - my),
      bottomLeft: Offset(mx, size.height - my),
    );
  }

  /// Corners in clockwise order [TL, TR, BR, BL].
  List<Offset> get points => [topLeft, topRight, bottomRight, bottomLeft];

  /// The four edge lengths [top, right, bottom, left].
  double get topEdge => (topRight - topLeft).distance;
  double get rightEdge => (bottomRight - topRight).distance;
  double get bottomEdge => (bottomRight - bottomLeft).distance;
  double get leftEdge => (bottomLeft - topLeft).distance;

  /// Estimated output width: the longer of the two horizontal edges. Using the
  /// max (not the average) keeps the whole document visible after warping.
  double get estimatedWidth => math.max(topEdge, bottomEdge);

  /// Estimated output height: the longer of the two vertical edges.
  double get estimatedHeight => math.max(leftEdge, rightEdge);

  /// Axis-aligned bounding box of the quad.
  Rect get boundingBox {
    final xs = points.map((p) => p.dx);
    final ys = points.map((p) => p.dy);
    final left = xs.reduce(math.min);
    final top = ys.reduce(math.min);
    return Rect.fromLTRB(left, top, xs.reduce(math.max), ys.reduce(math.max));
  }

  /// Signed polygon area via the shoelace formula (absolute value returned).
  double get area {
    final p = points;
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2.0;
  }

  /// Whether the quad is convex (all cross products share the same sign). A
  /// non-convex quad is a bad detection (self-intersecting / dented).
  bool get isConvex {
    final p = points;
    int? sign;
    for (var i = 0; i < 4; i++) {
      final a = p[i];
      final b = p[(i + 1) % 4];
      final c = p[(i + 2) % 4];
      final cross =
          (b.dx - a.dx) * (c.dy - b.dy) - (b.dy - a.dy) * (c.dx - b.dx);
      if (cross.abs() < 1e-9) continue; // collinear edge — ignore
      final s = cross > 0 ? 1 : -1;
      if (sign == null) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  /// Aspect ratio (width / height) of the estimated output.
  double get aspectRatio =>
      estimatedHeight == 0 ? 0 : estimatedWidth / estimatedHeight;

  /// Scale every corner (e.g. from preview space to raw pixel space).
  DocumentCorners scaled(double sx, double sy) => DocumentCorners(
        topLeft: Offset(topLeft.dx * sx, topLeft.dy * sy),
        topRight: Offset(topRight.dx * sx, topRight.dy * sy),
        bottomRight: Offset(bottomRight.dx * sx, bottomRight.dy * sy),
        bottomLeft: Offset(bottomLeft.dx * sx, bottomLeft.dy * sy),
      );

  /// Replace a single corner by index (0=TL,1=TR,2=BR,3=BL) — used by the
  /// manual crop editor when a handle is dragged.
  DocumentCorners withCorner(int index, Offset value) {
    return DocumentCorners(
      topLeft: index == 0 ? value : topLeft,
      topRight: index == 1 ? value : topRight,
      bottomRight: index == 2 ? value : bottomRight,
      bottomLeft: index == 3 ? value : bottomLeft,
    );
  }

  DocumentCorners clampToSize(Size size) => DocumentCorners(
        topLeft: _clamp(topLeft, size),
        topRight: _clamp(topRight, size),
        bottomRight: _clamp(bottomRight, size),
        bottomLeft: _clamp(bottomLeft, size),
      );

  static Offset _clamp(Offset p, Size size) => Offset(
        p.dx.clamp(0.0, size.width),
        p.dy.clamp(0.0, size.height),
      );

  @override
  bool operator ==(Object other) =>
      other is DocumentCorners &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode =>
      Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() =>
      'DocumentCorners(TL:$topLeft, TR:$topRight, BR:$bottomRight, BL:$bottomLeft)';
}
