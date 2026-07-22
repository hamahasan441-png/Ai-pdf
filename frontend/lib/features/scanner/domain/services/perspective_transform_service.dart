import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';

/// A 3x3 projective transform (homography) stored in row-major order:
///
/// ```
/// | m0 m1 m2 |
/// | m3 m4 m5 |
/// | m6 m7 m8 |
/// ```
///
/// Maps a source point `(x, y)` to `(x', y')` where
/// `x' = (m0·x + m1·y + m2) / (m6·x + m7·y + m8)` and similarly for `y'`.
class Homography {
  final List<double> m; // length 9

  const Homography(this.m);

  Offset map(Offset p) {
    final denom = m[6] * p.dx + m[7] * p.dy + m[8];
    if (denom == 0) return p;
    return Offset(
      (m[0] * p.dx + m[1] * p.dy + m[2]) / denom,
      (m[3] * p.dx + m[4] * p.dy + m[5]) / denom,
    );
  }
}

/// Computes and applies the perspective (projective) transform that maps the
/// detected document quad onto an upright rectangle — the "flatten / dewarp"
/// step that turns a photographed-at-an-angle page into a scanner-flat image.
///
/// The math is the canonical `getPerspectiveTransform`: from four point
/// correspondences we build an 8x8 linear system `A·h = b` (with `m8 = 1`) and
/// solve it by Gaussian elimination with partial pivoting. This is the same
/// approach OpenCV uses and is numerically robust for the well-conditioned
/// document-corner case.
///
/// Pure Dart (`dart:math` + `dart:ui` geometry) → fully unit-testable.
class PerspectiveTransformService {
  const PerspectiveTransformService();

  /// The output raster size that best preserves the document, derived from the
  /// quad's edge lengths. Optionally snapped toward a target aspect ratio.
  Size outputSize(DocumentCorners corners, {double maxDimension = 2400}) {
    var w = corners.estimatedWidth;
    var h = corners.estimatedHeight;
    if (w <= 0 || h <= 0) return const Size(1, 1);

    // Cap the longest side so warps stay memory-bounded (matches the editor's
    // render cap philosophy) while preserving aspect.
    final longest = math.max(w, h);
    if (longest > maxDimension) {
      final scale = maxDimension / longest;
      w *= scale;
      h *= scale;
    }
    return Size(w.roundToDouble(), h.roundToDouble());
  }

  /// The homography mapping the *destination* rectangle (0..w, 0..h) back to
  /// the *source* quad. This "inverse" direction is what a warp sampler wants:
  /// for each output pixel, find where to read from the source.
  Homography destToSrc(DocumentCorners corners, Size dst) {
    final srcPts = corners.points;
    final dstPts = <Offset>[
      const Offset(0, 0),
      Offset(dst.width, 0),
      Offset(dst.width, dst.height),
      Offset(0, dst.height),
    ];
    return _solve(dstPts, srcPts);
  }

  /// The homography mapping the source quad onto the destination rectangle
  /// (forward direction) — useful for projecting detected points into the
  /// flattened output space.
  Homography srcToDest(DocumentCorners corners, Size dst) {
    final srcPts = corners.points;
    final dstPts = <Offset>[
      const Offset(0, 0),
      Offset(dst.width, 0),
      Offset(dst.width, dst.height),
      Offset(0, dst.height),
    ];
    return _solve(srcPts, dstPts);
  }

  /// Solve for the homography mapping [from]\[i] -> [to]\[i] (4 correspondences).
  Homography _solve(List<Offset> from, List<Offset> to) {
    // Build the 8x8 system for the 8 unknowns (m0..m7), fixing m8 = 1.
    // For each correspondence (x,y) -> (u,v):
    //   m0·x + m1·y + m2 - m6·x·u - m7·y·u = u
    //   m3·x + m4·y + m5 - m6·x·v - m7·y·v = v
    final a = List.generate(8, (_) => List<double>.filled(8, 0.0));
    final b = List<double>.filled(8, 0.0);

    for (var i = 0; i < 4; i++) {
      final x = from[i].dx, y = from[i].dy;
      final u = to[i].dx, v = to[i].dy;

      final r0 = i * 2;
      a[r0][0] = x;
      a[r0][1] = y;
      a[r0][2] = 1;
      a[r0][6] = -x * u;
      a[r0][7] = -y * u;
      b[r0] = u;

      final r1 = i * 2 + 1;
      a[r1][3] = x;
      a[r1][4] = y;
      a[r1][5] = 1;
      a[r1][6] = -x * v;
      a[r1][7] = -y * v;
      b[r1] = v;
    }

    final h = _gaussianSolve(a, b);
    return Homography([
      h[0], h[1], h[2],
      h[3], h[4], h[5],
      h[6], h[7], 1.0,
    ]);
  }

  /// Gaussian elimination with partial pivoting for an NxN system A·x = b.
  List<double> _gaussianSolve(List<List<double>> a, List<double> b) {
    final n = b.length;
    // Work on copies.
    final m = [for (final row in a) [...row]];
    final rhs = [...b];

    for (var col = 0; col < n; col++) {
      // Partial pivot: find the row with the largest |value| in this column.
      var pivot = col;
      var maxVal = m[col][col].abs();
      for (var r = col + 1; r < n; r++) {
        final v = m[r][col].abs();
        if (v > maxVal) {
          maxVal = v;
          pivot = r;
        }
      }
      if (maxVal < 1e-12) {
        continue; // singular column; leave as-is (degenerate input)
      }
      if (pivot != col) {
        final tmp = m[col];
        m[col] = m[pivot];
        m[pivot] = tmp;
        final tb = rhs[col];
        rhs[col] = rhs[pivot];
        rhs[pivot] = tb;
      }
      // Eliminate below.
      for (var r = col + 1; r < n; r++) {
        final factor = m[r][col] / m[col][col];
        if (factor == 0) continue;
        for (var c = col; c < n; c++) {
          m[r][c] -= factor * m[col][c];
        }
        rhs[r] -= factor * rhs[col];
      }
    }

    // Back-substitution.
    final x = List<double>.filled(n, 0.0);
    for (var row = n - 1; row >= 0; row--) {
      var sum = rhs[row];
      for (var c = row + 1; c < n; c++) {
        sum -= m[row][c] * x[c];
      }
      final diag = m[row][row];
      x[row] = diag.abs() < 1e-12 ? 0.0 : sum / diag;
    }
    return x;
  }
}
