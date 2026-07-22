import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';

/// Orders four arbitrary points into the canonical TL, TR, BR, BL layout.
///
/// Uses the well-known sum/difference heuristic (the same one OpenCV document
/// scanner tutorials use), which is robust to rotation up to ~45°:
///
/// - **Top-left**  has the smallest `x + y`.
/// - **Bottom-right** has the largest `x + y`.
/// - **Top-right** has the smallest `y - x`.
/// - **Bottom-left** has the largest `y - x`.
///
/// A geometric fallback (angle around the centroid) handles the degenerate
/// cases the sum/diff method can misassign (e.g. a diamond rotated near 45°),
/// guaranteeing a valid clockwise quad for any 4 distinct points.
class CornerOrderingService {
  const CornerOrderingService();

  /// Order exactly four [points]. Throws [ArgumentError] if not four points.
  DocumentCorners order(List<Offset> points) {
    if (points.length != 4) {
      throw ArgumentError('Expected exactly 4 points, got ${points.length}');
    }

    final byOrdering = _orderBySumDiff(points);
    // A correct assignment is convex with four distinct corners.
    if (byOrdering != null && byOrdering.isConvex) {
      return byOrdering;
    }
    // Fallback: sort clockwise around the centroid, rotate top-left first.
    return _orderByAngle(points);
  }

  /// Order any contour's [points] (>=4) by taking its extreme points as the
  /// quad corners — useful when a detector returns many boundary points.
  DocumentCorners orderFromContour(List<Offset> points) {
    if (points.length < 4) {
      throw ArgumentError('Need at least 4 points, got ${points.length}');
    }
    return _extremes(points);
  }

  DocumentCorners? _orderBySumDiff(List<Offset> points) {
    final quad = _extremes(points);
    final set = {quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft};
    if (set.length != 4) return null;
    return quad;
  }

  DocumentCorners _extremes(List<Offset> points) {
    Offset tl = points.first, tr = points.first, br = points.first, bl = points.first;
    var minSum = double.infinity, maxSum = -double.infinity;
    var minDiff = double.infinity, maxDiff = -double.infinity;
    for (final p in points) {
      final sum = p.dx + p.dy;
      final diff = p.dy - p.dx;
      if (sum < minSum) {
        minSum = sum;
        tl = p;
      }
      if (sum > maxSum) {
        maxSum = sum;
        br = p;
      }
      if (diff < minDiff) {
        minDiff = diff;
        tr = p;
      }
      if (diff > maxDiff) {
        maxDiff = diff;
        bl = p;
      }
    }
    return DocumentCorners(
        topLeft: tl, topRight: tr, bottomRight: br, bottomLeft: bl);
  }

  DocumentCorners _orderByAngle(List<Offset> points) {
    final cx = points.map((p) => p.dx).reduce((a, b) => a + b) / points.length;
    final cy = points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
    final sorted = [...points]..sort((a, b) {
        final angA = math.atan2(a.dy - cy, a.dx - cx);
        final angB = math.atan2(b.dy - cy, b.dx - cx);
        return angA.compareTo(angB);
      });
    // `sorted` is clockwise in screen coords (y down). Rotate so the corner
    // nearest the origin (top-left-most) is first.
    var startIdx = 0;
    var best = double.infinity;
    for (var i = 0; i < sorted.length; i++) {
      final d = sorted[i].dx + sorted[i].dy;
      if (d < best) {
        best = d;
        startIdx = i;
      }
    }
    final rotated = [for (var i = 0; i < 4; i++) sorted[(startIdx + i) % 4]];
    return DocumentCorners(
      topLeft: rotated[0],
      topRight: rotated[1],
      bottomRight: rotated[2],
      bottomLeft: rotated[3],
    );
  }
}
