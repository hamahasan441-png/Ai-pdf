import 'dart:math' as math;

/// The result of evaluating whether a live frame is good enough to auto-capture.
class StabilityResult {
  /// Variance of the Laplacian — higher means sharper (less blur).
  final double sharpness;

  /// Mean absolute frame difference — higher means more motion.
  final double motion;

  final bool sharpEnough;
  final bool still;

  const StabilityResult({
    required this.sharpness,
    required this.motion,
    required this.sharpEnough,
    required this.still,
  });

  /// True when the frame is both sharp and steady — safe to auto-capture.
  bool get readyToCapture => sharpEnough && still;
}

/// Decides when a live camera frame is stable and sharp enough to auto-capture,
/// the hallmark of a professional scanner (no shutter button needed).
///
/// - **Sharpness** uses the *variance of the Laplacian* — the classic,
///   fast focus/blur metric: a blurry frame has a smooth Laplacian (low
///   variance), a sharp frame has strong edges (high variance).
/// - **Motion** is the mean absolute difference between consecutive frames.
///
/// Both operate on downscaled grayscale grids (`List<int>`, 0..255, row-major),
/// so the detector is pure Dart, cheap to run per preview frame, and fully
/// unit-testable.
class ScanStabilityDetector {
  const ScanStabilityDetector();

  /// Default sharpness cutoff (variance of Laplacian on 0..255 data). Tunable
  /// per device; ~100 is a common blur threshold in the literature.
  static const double defaultSharpnessThreshold = 100.0;

  /// Default motion cutoff (mean abs diff per pixel, 0..255 scale).
  static const double defaultMotionThreshold = 6.0;

  /// Variance of the Laplacian over the interior pixels of [gray].
  double blurScore(List<int> gray, int width, int height) {
    if (width < 3 || height < 3 || gray.length != width * height) return 0.0;
    var sum = 0.0;
    var sumSq = 0.0;
    var count = 0;
    for (var y = 1; y < height - 1; y++) {
      for (var x = 1; x < width - 1; x++) {
        final c = gray[y * width + x];
        final lap = (gray[(y - 1) * width + x] +
                gray[(y + 1) * width + x] +
                gray[y * width + (x - 1)] +
                gray[y * width + (x + 1)] -
                4 * c)
            .toDouble();
        sum += lap;
        sumSq += lap * lap;
        count++;
      }
    }
    if (count == 0) return 0.0;
    final mean = sum / count;
    return math.max(0.0, sumSq / count - mean * mean);
  }

  /// Mean absolute per-pixel difference between two equally-sized frames.
  double motionScore(List<int> current, List<int> previous) {
    if (current.length != previous.length || current.isEmpty) {
      return double.infinity; // unknown / not comparable -> treat as moving
    }
    var total = 0.0;
    for (var i = 0; i < current.length; i++) {
      total += (current[i] - previous[i]).abs();
    }
    return total / current.length;
  }

  /// Evaluate a frame. [previous] may be null on the very first frame (then
  /// motion is treated as "moving" so we don't fire instantly).
  StabilityResult evaluate(
    List<int> current,
    List<int>? previous,
    int width,
    int height, {
    double sharpnessThreshold = defaultSharpnessThreshold,
    double motionThreshold = defaultMotionThreshold,
  }) {
    final sharpness = blurScore(current, width, height);
    final motion =
        previous == null ? double.infinity : motionScore(current, previous);
    return StabilityResult(
      sharpness: sharpness,
      motion: motion,
      sharpEnough: sharpness >= sharpnessThreshold,
      still: motion <= motionThreshold,
    );
  }
}
