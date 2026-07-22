import 'dart:math' as math;

/// Adaptive document binarization producing a crisp black-on-white scan.
///
/// Implements **Sauvola's local thresholding** (the standard for document
/// binarization, robust to uneven lighting and shadows that break a single
/// global threshold):
///
/// ```
/// T(x,y) = m(x,y) · [ 1 + k · ( s(x,y)/R − 1 ) ]
/// ```
///
/// where `m` and `s` are the local mean and standard deviation over a window
/// around each pixel, `R` is the dynamic range of std (128 for 8-bit), and `k`
/// is a tuning constant (0.2–0.5; 0.2 is the classic recommendation). A pixel
/// is white when its value is above `T`, else black.
///
/// The per-pixel window statistics are computed in O(1) using **integral
/// images** (summed-area tables) for the sum and the sum of squares, so the
/// whole pass is O(width·height) regardless of window size — the efficient
/// formulation from Shafait et al.
///
/// Also provides a global **Otsu** threshold for the simple high-contrast case.
///
/// Operates on a flat grayscale buffer (`List<int>` of 0..255, row-major) so it
/// is pure Dart, isolate-safe and fully unit-testable.
class ScanBinarizationService {
  const ScanBinarizationService();

  /// Sauvola binarization. Returns a new buffer where each pixel is 0 or 255.
  ///
  /// [window] is the side length of the local neighbourhood (odd, e.g. 15–31),
  /// [k] the Sauvola constant, [r] the std dynamic range.
  List<int> sauvola(
    List<int> gray,
    int width,
    int height, {
    int window = 25,
    double k = 0.2,
    double r = 128.0,
  }) {
    final n = width * height;
    if (gray.length != n || n == 0) {
      throw ArgumentError('gray length must equal width*height');
    }
    final half = (window ~/ 2).clamp(1, math.max(width, height));

    // Integral images with a 1-pixel zero border: size (w+1) x (h+1).
    final iw = width + 1;
    final sum = List<double>.filled(iw * (height + 1), 0.0);
    final sqSum = List<double>.filled(iw * (height + 1), 0.0);

    for (var y = 0; y < height; y++) {
      var rowSum = 0.0;
      var rowSqSum = 0.0;
      for (var x = 0; x < width; x++) {
        final v = gray[y * width + x].toDouble();
        rowSum += v;
        rowSqSum += v * v;
        final idx = (y + 1) * iw + (x + 1);
        sum[idx] = sum[y * iw + (x + 1)] + rowSum;
        sqSum[idx] = sqSum[y * iw + (x + 1)] + rowSqSum;
      }
    }

    final out = List<int>.filled(n, 0);
    for (var y = 0; y < height; y++) {
      final y0 = (y - half).clamp(0, height - 1);
      final y1 = (y + half).clamp(0, height - 1);
      for (var x = 0; x < width; x++) {
        final x0 = (x - half).clamp(0, width - 1);
        final x1 = (x + half).clamp(0, width - 1);

        final count = (x1 - x0 + 1) * (y1 - y0 + 1);
        final s = _rectSum(sum, iw, x0, y0, x1, y1);
        final sq = _rectSum(sqSum, iw, x0, y0, x1, y1);

        final mean = s / count;
        final variance = math.max(0.0, sq / count - mean * mean);
        final std = math.sqrt(variance);
        final t = mean * (1 + k * (std / r - 1));

        out[y * width + x] = gray[y * width + x] > t ? 255 : 0;
      }
    }
    return out;
  }

  /// Otsu's global threshold (0..255) that maximises between-class variance.
  int otsuThreshold(List<int> gray) {
    final hist = List<int>.filled(256, 0);
    for (final v in gray) {
      hist[v.clamp(0, 255)]++;
    }
    final total = gray.length;
    if (total == 0) return 127;

    var sumAll = 0.0;
    for (var i = 0; i < 256; i++) {
      sumAll += i * hist[i];
    }

    var sumB = 0.0;
    var wB = 0;
    var maxVar = -1.0;
    var threshold = 127;

    for (var t = 0; t < 256; t++) {
      wB += hist[t];
      if (wB == 0) continue;
      final wF = total - wB;
      if (wF == 0) break;
      sumB += t * hist[t];
      final mB = sumB / wB;
      final mF = (sumAll - sumB) / wF;
      final between = wB.toDouble() * wF.toDouble() * (mB - mF) * (mB - mF);
      if (between > maxVar) {
        maxVar = between;
        threshold = t;
      }
    }
    return threshold;
  }

  /// Apply a global threshold, returning a 0/255 buffer.
  List<int> applyThreshold(List<int> gray, int threshold) =>
      [for (final v in gray) v > threshold ? 255 : 0];

  double _rectSum(
      List<double> integral, int iw, int x0, int y0, int x1, int y1) {
    // Inclusive rect [x0,x1] x [y0,y1] in original coords; integral is offset
    // by +1 on each axis (border), so the standard summed-area formula is:
    final a = integral[y0 * iw + x0];
    final b = integral[y0 * iw + (x1 + 1)];
    final c = integral[(y1 + 1) * iw + x0];
    final d = integral[(y1 + 1) * iw + (x1 + 1)];
    return d - b - c + a;
  }
}
