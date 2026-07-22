import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';
import 'package:ai_pdf/features/scanner/domain/services/corner_ordering_service.dart';

/// The result of a document-boundary detection.
class DocumentDetectionResult {
  final DocumentCorners corners;

  /// 0..1 — how confident the detector is that this is a real document edge
  /// (vs. a full-frame fallback).
  final double confidence;

  /// True when this is the safe full-frame fallback rather than a real edge.
  final bool isFallback;

  const DocumentDetectionResult({
    required this.corners,
    required this.confidence,
    required this.isFallback,
  });
}

/// Selects and validates the best document quadrilateral from candidate edges,
/// and can estimate a boundary from coarse edge-energy profiles.
///
/// Two entry points:
/// - [detectBest] picks the highest-scoring valid quad from a set of candidate
///   contour point-sets (produced by the pixel-level edge/contour pass in the
///   image layer), falling back to an inset full frame when nothing qualifies.
/// - [estimateFromEnergy] derives an axis-aligned boundary from per-row and
///   per-column edge-energy arrays — a fast, robust boundary for the common
///   "dark-ish document on a plain background" case, and fully testable with
///   synthetic profiles.
///
/// Pure Dart → fully unit-testable.
class DocumentDetectionService {
  const DocumentDetectionService();

  static const _ordering = CornerOrderingService();

  /// Minimum fraction of the frame area a valid document must cover.
  static const double minAreaRatio = 0.10;

  /// Maximum fraction (a quad filling ~the whole frame is usually the frame
  /// itself, not a detected document — but we still allow it as low-confidence).
  static const double maxAreaRatio = 0.999;

  /// Acceptable output aspect-ratio band (width/height). Covers portrait A4
  /// (~0.71), landscape (~1.41), letter, receipts, business cards, etc.
  static const double minAspect = 0.15;
  static const double maxAspect = 6.5;

  /// Pick the best document quad from [candidates] (each a list of >=4 points),
  /// scoring by area coverage, rectangularity and convexity. Falls back to an
  /// inset full frame when none qualify.
  DocumentDetectionResult detectBest(
    List<List<Offset>> candidates,
    Size frame,
  ) {
    DocumentCorners? best;
    var bestScore = 0.0;

    for (final pts in candidates) {
      if (pts.length < 4) continue;
      final quad = pts.length == 4
          ? _ordering.order(pts)
          : _ordering.orderFromContour(pts);
      final score = scoreQuad(quad, frame);
      if (score > bestScore) {
        bestScore = score;
        best = quad;
      }
    }

    if (best != null && bestScore > 0) {
      return DocumentDetectionResult(
        corners: best.clampToSize(frame),
        confidence: bestScore,
        isFallback: false,
      );
    }
    // Fallback: a slightly inset frame so the user has handles to drag.
    return DocumentDetectionResult(
      corners: DocumentCorners.insetFrame(frame, 0.04),
      confidence: 0.0,
      isFallback: true,
    );
  }

  /// Whether [corners] is a plausible document within [frame].
  bool isValidDocumentQuad(DocumentCorners corners, Size frame) {
    if (!corners.isConvex) return false;
    final frameArea = frame.width * frame.height;
    if (frameArea <= 0) return false;
    final ratio = corners.area / frameArea;
    if (ratio < minAreaRatio || ratio > maxAreaRatio) return false;
    final aspect = corners.aspectRatio;
    if (aspect < minAspect || aspect > maxAspect) return false;
    // Reject degenerate quads where any edge is tiny relative to the frame.
    final minEdge = math.min(
      math.min(corners.topEdge, corners.bottomEdge),
      math.min(corners.leftEdge, corners.rightEdge),
    );
    final frameMin = math.min(frame.width, frame.height);
    if (minEdge < frameMin * 0.05) return false;
    return true;
  }

  /// Score a quad in 0..1. Higher = more likely a real, well-framed document.
  double scoreQuad(DocumentCorners corners, Size frame) {
    if (!isValidDocumentQuad(corners, frame)) return 0.0;
    final frameArea = frame.width * frame.height;
    final ratio = (corners.area / frameArea).clamp(0.0, 1.0);

    // Prefer documents that fill a good part of the frame but aren't the whole
    // frame — peak preference around 65% coverage.
    final coverageScore = 1.0 - ((ratio - 0.65).abs() / 0.65).clamp(0.0, 1.0);

    // Rectangularity: opposite edges similar length, corners near right angles.
    final wSym = _symmetry(corners.topEdge, corners.bottomEdge);
    final hSym = _symmetry(corners.leftEdge, corners.rightEdge);
    final rectScore = (wSym + hSym) / 2.0;

    // Right-angle score: how close the four interior angles are to 90°.
    final angleScore = _rightAngleScore(corners);

    return (coverageScore * 0.4 + rectScore * 0.35 + angleScore * 0.25)
        .clamp(0.0, 1.0);
  }

  /// Estimate an axis-aligned document boundary from 1D edge-energy profiles.
  ///
  /// [rowEnergy]\[y] and [colEnergy]\[x] are the summed gradient magnitude for
  /// each row / column (from a downscaled grayscale pass). The document is the
  /// contiguous central band whose energy exceeds a fraction of the peak.
  DocumentDetectionResult estimateFromEnergy(
    List<double> rowEnergy,
    List<double> colEnergy,
    Size frame, {
    double threshold = 0.15,
  }) {
    final yBand = _energyBand(rowEnergy, threshold);
    final xBand = _energyBand(colEnergy, threshold);
    if (yBand == null || xBand == null) {
      return DocumentDetectionResult(
        corners: DocumentCorners.insetFrame(frame, 0.04),
        confidence: 0.0,
        isFallback: true,
      );
    }

    final h = rowEnergy.length;
    final w = colEnergy.length;
    final top = yBand[0] / h * frame.height;
    final bottom = (yBand[1] + 1) / h * frame.height;
    final left = xBand[0] / w * frame.width;
    final right = (xBand[1] + 1) / w * frame.width;

    final corners = DocumentCorners(
      topLeft: Offset(left, top),
      topRight: Offset(right, top),
      bottomRight: Offset(right, bottom),
      bottomLeft: Offset(left, bottom),
    );

    final valid = isValidDocumentQuad(corners, frame);
    return DocumentDetectionResult(
      corners: valid ? corners : DocumentCorners.insetFrame(frame, 0.04),
      confidence: valid ? 0.6 : 0.0,
      isFallback: !valid,
    );
  }

  // --- internals -----------------------------------------------------------

  /// Symmetry of two lengths in 0..1 (1 = equal).
  double _symmetry(double a, double b) {
    final maxV = math.max(a, b);
    if (maxV <= 0) return 0;
    return (math.min(a, b) / maxV).clamp(0.0, 1.0);
  }

  double _rightAngleScore(DocumentCorners c) {
    final p = c.points;
    var total = 0.0;
    for (var i = 0; i < 4; i++) {
      final prev = p[(i + 3) % 4];
      final cur = p[i];
      final next = p[(i + 1) % 4];
      final v1 = prev - cur;
      final v2 = next - cur;
      final dot = v1.dx * v2.dx + v1.dy * v2.dy;
      final mag = v1.distance * v2.distance;
      if (mag == 0) continue;
      final cosang = (dot / mag).clamp(-1.0, 1.0);
      final angle = math.acos(cosang); // radians
      // 1.0 at exactly 90°, decaying toward 0 as it deviates by 90°.
      final deviation = (angle - math.pi / 2).abs();
      total += (1.0 - (deviation / (math.pi / 2))).clamp(0.0, 1.0);
    }
    return total / 4.0;
  }

  /// Find the [start, end] index band where energy exceeds `threshold * peak`,
  /// taking the largest contiguous run. Returns null if nothing qualifies.
  List<int>? _energyBand(List<double> energy, double threshold) {
    if (energy.isEmpty) return null;
    final peak = energy.reduce(math.max);
    if (peak <= 0) return null;
    final cut = peak * threshold;

    var bestStart = -1;
    var bestEnd = -1;
    var bestLen = -1;
    var runStart = -1; // -1 means "not currently in a run"

    void closeRun(int endInclusive) {
      if (runStart < 0) return;
      final len = endInclusive - runStart;
      if (len > bestLen) {
        bestLen = len;
        bestStart = runStart;
        bestEnd = endInclusive;
      }
      runStart = -1;
    }

    for (var i = 0; i < energy.length; i++) {
      if (energy[i] >= cut) {
        if (runStart < 0) runStart = i;
      } else {
        closeRun(i - 1);
      }
    }
    closeRun(energy.length - 1);

    if (bestStart < 0) return null;
    return [bestStart, bestEnd];
  }
}
