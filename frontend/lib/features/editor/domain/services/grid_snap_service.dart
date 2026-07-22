import 'dart:ui' show Offset, Rect;

/// The outcome of a threshold-based grid snap (Phase 20).
///
/// [point] is the (possibly) adjusted position. [guideX] / [guideY] are the
/// gridlines the point snapped to (null when no snap happened on that axis),
/// so the UI can draw alignment guides.
class GridSnapResult {
  final Offset point;
  final double? guideX;
  final double? guideY;

  const GridSnapResult(this.point, {this.guideX, this.guideY});

  bool get snapped => guideX != null || guideY != null;
}

/// Snaps points and rects to a configurable grid (Phase 20).
///
/// Complements the existing object‑to‑object smart guides (Phase 7) with a
/// classic layout grid: values, points and rectangles snap to the nearest
/// gridline. [snapNear] only snaps when the point is within a threshold of a
/// line (so free movement between lines still feels smooth) and reports which
/// gridlines were hit for drawing guides.
///
/// All coordinates are in the editor's normalised 0..1 page space. Pure Dart +
/// `dart:ui` geometry → fully unit‑testable.
class GridSnapService {
  const GridSnapService();

  /// Round [v] to the nearest multiple of [grid]. A non‑positive [grid]
  /// disables snapping and returns [v] unchanged.
  double snapValue(double v, double grid) {
    if (grid <= 0) return v;
    return (v / grid).round() * grid;
  }

  /// Snap a point to the grid on both axes (always snaps).
  Offset snapPoint(Offset p, {required double gridX, required double gridY}) {
    return Offset(snapValue(p.dx, gridX), snapValue(p.dy, gridY));
  }

  /// Snap a rectangle to the grid.
  ///
  /// The top‑left always snaps. When [snapSize] is true the width/height also
  /// snap to grid multiples (min one cell); otherwise the size is preserved
  /// and only the position changes.
  Rect snapRect(
    Rect r, {
    required double gridX,
    required double gridY,
    bool snapSize = false,
  }) {
    final left = snapValue(r.left, gridX);
    final top = snapValue(r.top, gridY);
    if (!snapSize) {
      return Rect.fromLTWH(left, top, r.width, r.height);
    }
    final w = _atLeast(snapValue(r.width, gridX), gridX);
    final h = _atLeast(snapValue(r.height, gridY), gridY);
    return Rect.fromLTWH(left, top, w, h);
  }

  /// Snap [p] only if it is within [threshold] of a gridline on that axis.
  ///
  /// Returns the adjusted point plus the gridlines it locked onto (for guides).
  GridSnapResult snapNear(
    Offset p, {
    required double gridX,
    required double gridY,
    double threshold = 0.01,
  }) {
    double? gx;
    double? gy;
    var x = p.dx;
    var y = p.dy;

    if (gridX > 0) {
      final candidate = snapValue(p.dx, gridX);
      if ((candidate - p.dx).abs() <= threshold) {
        x = candidate;
        gx = candidate;
      }
    }
    if (gridY > 0) {
      final candidate = snapValue(p.dy, gridY);
      if ((candidate - p.dy).abs() <= threshold) {
        y = candidate;
        gy = candidate;
      }
    }
    return GridSnapResult(Offset(x, y), guideX: gx, guideY: gy);
  }

  double _atLeast(double v, double floor) => v < floor ? floor : v;
}
