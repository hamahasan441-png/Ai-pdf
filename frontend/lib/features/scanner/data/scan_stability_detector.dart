/// The result of evaluating whether a live frame is good enough to auto-capture.
class StabilityResult {
  /// Sharpness metric — higher means sharper (less blur).
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

/// Decides when a live camera frame is stable and sharp enough to auto-capture.
///
/// - **Sharpness** uses average absolute neighbor difference — flat images
///   score near zero, high-frequency patterns (like a checkerboard) score high.
/// - **Motion** is the mean absolute per-pixel difference between consecutive
///   frames. Returns [double.infinity] when frames cannot be compared (null
///   previous, mismatched sizes).
///
/// Both operate on downscaled grayscale grids (`List<int>`, 0..255, row-major),
/// so the detector is pure Dart, cheap to run per preview frame, and fully
/// unit-testable.
class ScanStabilityDetector {
  const ScanStabilityDetector();

  /// Default sharpness cutoff. A checkerboard easily exceeds this; a flat
  /// (uniform) image produces ~0.
  static const double defaultSharpnessThreshold = 10.0;

  /// Default motion cutoff (mean abs diff per pixel, 0..255 scale).
  static const double defaultMotionThreshold = 5.0;

  /// Sharpness metric: average absolute difference between each pixel and its
  /// right and bottom neighbors. A uniform image → 0; a checkerboard → ~255.
  ///
  /// Returns 0 for degenerate sizes (width ≤ 1 or height ≤ 1 or length mismatch).
  double blurScore(List<int> gray, int width, int height) {
    if (width <= 1 || height <= 1) return 0.0;
    if (gray.length != width * height) return 0.0;

    double sumDiff = 0.0;
    int count = 0;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final int idx = y * width + x;
        final int v = gray[idx];

        if (x + 1 < width) {
          sumDiff += (v - gray[y * width + (x + 1)]).abs();
          count++;
        }
        if (y + 1 < height) {
          sumDiff += (v - gray[(y + 1) * width + x]).abs();
          count++;
        }
      }
    }

    if (count == 0) return 0.0;
    return sumDiff / count;
  }

  /// Mean absolute per-pixel difference between two frames.
  ///
  /// Returns [double.infinity] if [previous] is null or sizes don't match
  /// (treat as "moving" / not comparable).
  double motionScore(List<int> current, List<int>? previous) {
    if (previous == null) return double.infinity;
    if (current.length != previous.length) return double.infinity;
    if (current.isEmpty) return 0.0;

    double sum = 0.0;
    for (var i = 0; i < current.length; i++) {
      sum += (current[i] - previous[i]).abs();
    }
    return sum / current.length;
  }

  /// Evaluate a frame for auto-capture readiness.
  ///
  /// [previous] may be null on the very first frame (motion is then treated as
  /// infinity so we don't fire instantly).
  StabilityResult evaluate(
    List<int> current,
    List<int>? previous,
    int width,
    int height, {
    double sharpnessThreshold = defaultSharpnessThreshold,
    double motionThreshold = defaultMotionThreshold,
  }) {
    final sharpness = blurScore(current, width, height);
    final motion = motionScore(current, previous);

    return StabilityResult(
      sharpness: sharpness,
      motion: motion,
      sharpEnough: sharpness > sharpnessThreshold,
      still: motion.isFinite && motion < motionThreshold,
    );
  }
}
