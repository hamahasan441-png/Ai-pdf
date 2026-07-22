import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:image/image.dart' as img;

import 'package:ai_pdf/features/scanner/data/scan_binarization_service.dart';
import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_filter.dart';
import 'package:ai_pdf/features/scanner/domain/services/document_detection_service.dart';
import 'package:ai_pdf/features/scanner/domain/services/perspective_transform_service.dart';

/// Coarse detection input extracted from a captured frame: a downscaled
/// grayscale grid plus per-row / per-column edge-energy profiles, all in the
/// downscaled space (with the scale factor to map back to full resolution).
class ScanDetectionInput {
  final List<int> gray; // downscaled luminance, row-major 0..255
  final int width;
  final int height;
  final List<double> rowEnergy;
  final List<double> colEnergy;

  /// Full-resolution frame size (for mapping detected corners back).
  final Size fullSize;

  const ScanDetectionInput({
    required this.gray,
    required this.width,
    required this.height,
    required this.rowEnergy,
    required this.colEnergy,
    required this.fullSize,
  });
}

/// The image-processing engine for the scanner: decode, coarse edge extraction,
/// perspective dewarp, and enhancement filters. Uses the pure-Dart `image`
/// package so it can run in a background isolate via `compute`.
///
/// The precise geometry/threshold math lives in the domain services
/// ([PerspectiveTransformService], [DocumentDetectionService],
/// [ScanBinarizationService]); this class binds them to real pixels.
class ScanImageProcessor {
  const ScanImageProcessor();

  static const _perspective = PerspectiveTransformService();
  static const _binarizer = ScanBinarizationService();

  /// Decode [bytes] and build a coarse [ScanDetectionInput] for boundary
  /// detection. The frame is downscaled so [maxSample] is the long edge, which
  /// keeps detection fast and stable.
  ScanDetectionInput? extractDetectionInput(Uint8List bytes,
      {int maxSample = 320}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final fullSize =
        Size(decoded.width.toDouble(), decoded.height.toDouble());

    final longEdge =
        decoded.width > decoded.height ? decoded.width : decoded.height;
    final scale = longEdge > maxSample ? maxSample / longEdge : 1.0;
    var sw = (decoded.width * scale).round();
    var sh = (decoded.height * scale).round();
    if (sw < 1) sw = 1;
    if (sh < 1) sh = 1;
    final small = img.copyResize(decoded, width: sw, height: sh);

    // Grayscale grid.
    final gray = List<int>.filled(sw * sh, 0);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < sw; x++) {
        final p = small.getPixel(x, y);
        gray[y * sw + x] = _luma(p.r, p.g, p.b);
      }
    }

    // Sobel gradient magnitude accumulated per row and per column.
    final rowEnergy = List<double>.filled(sh, 0.0);
    final colEnergy = List<double>.filled(sw, 0.0);
    for (var y = 1; y < sh - 1; y++) {
      for (var x = 1; x < sw - 1; x++) {
        final gx = -gray[(y - 1) * sw + (x - 1)] +
            gray[(y - 1) * sw + (x + 1)] +
            -2 * gray[y * sw + (x - 1)] +
            2 * gray[y * sw + (x + 1)] +
            -gray[(y + 1) * sw + (x - 1)] +
            gray[(y + 1) * sw + (x + 1)];
        final gy = -gray[(y - 1) * sw + (x - 1)] -
            2 * gray[(y - 1) * sw + x] -
            gray[(y - 1) * sw + (x + 1)] +
            gray[(y + 1) * sw + (x - 1)] +
            2 * gray[(y + 1) * sw + x] +
            gray[(y + 1) * sw + (x + 1)];
        final mag = math.sqrt((gx * gx + gy * gy).toDouble());
        rowEnergy[y] += mag;
        colEnergy[x] += mag;
      }
    }

    return ScanDetectionInput(
      gray: gray,
      width: sw,
      height: sh,
      rowEnergy: rowEnergy,
      colEnergy: colEnergy,
      fullSize: fullSize,
    );
  }

  /// Full pipeline: decode -> perspective dewarp using [corners] -> optional
  /// quarter-turn rotation -> [filter] -> JPEG encode. Returns null on failure.
  Uint8List? process({
    required Uint8List sourceBytes,
    required DocumentCorners corners,
    required ScanFilter filter,
    int rotationQuarterTurns = 0,
    int maxDimension = 2400,
    int jpegQuality = 90,
  }) {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return null;

    final outSize =
        _perspective.outputSize(corners, maxDimension: maxDimension.toDouble());
    var warped = _warp(decoded, corners, outSize);

    final turns = rotationQuarterTurns % 4;
    if (turns != 0) {
      warped = img.copyRotate(warped, angle: turns * 90);
    }

    final filtered = applyFilter(warped, filter);
    return Uint8List.fromList(img.encodeJpg(filtered, quality: jpegQuality));
  }

  /// Perspective-dewarp [src] so [corners] fills an upright [outSize] raster.
  /// For each output pixel we map back to the source via the dest->src
  /// homography and bilinearly sample — the standard inverse-warp.
  img.Image _warp(img.Image src, DocumentCorners corners, Size outSize) {
    var w = outSize.width.round();
    var h = outSize.height.round();
    if (w < 1) w = 1;
    if (h < 1) h = 1;
    if (w > 100000) w = 100000;
    if (h > 100000) h = 100000;
    final out = img.Image(width: w, height: h);
    final hMat = _perspective.destToSrc(corners, Size(w.toDouble(), h.toDouble()));

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final s = hMat.map(Offset(x.toDouble(), y.toDouble()));
        final rgb = _bilinear(src, s.dx, s.dy);
        out.setPixelRgb(x, y, rgb[0], rgb[1], rgb[2]);
      }
    }
    return out;
  }

  /// Apply an enhancement [filter] to an already-dewarped image.
  img.Image applyFilter(img.Image image, ScanFilter filter) {
    switch (filter) {
      case ScanFilter.original:
        return image;
      case ScanFilter.grayscale:
        return _grayscale(image);
      case ScanFilter.auto:
        return _magicColor(image);
      case ScanFilter.photo:
        return _photo(image);
      case ScanFilter.blackWhite:
        return _blackWhite(image);
    }
  }

  // --- filters -------------------------------------------------------------

  img.Image _grayscale(img.Image image) {
    final out = img.Image(width: image.width, height: image.height);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final l = _luma(p.r, p.g, p.b);
        out.setPixelRgb(x, y, l, l, l);
      }
    }
    return out;
  }

  /// White balance (per-channel percentile stretch) + contrast — the "magic
  /// colour" look: bright white paper, saturated ink, no colour cast.
  img.Image _magicColor(img.Image image) {
    final loR = _percentile(image, 0, 0.02);
    final hiR = _percentile(image, 0, 0.98);
    final loG = _percentile(image, 1, 0.02);
    final hiG = _percentile(image, 1, 0.98);
    final loB = _percentile(image, 2, 0.02);
    final hiB = _percentile(image, 2, 0.98);

    final out = img.Image(width: image.width, height: image.height);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final r = _stretch(p.r.toInt(), loR, hiR);
        final g = _stretch(p.g.toInt(), loG, hiG);
        final b = _stretch(p.b.toInt(), loB, hiB);
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  img.Image _photo(img.Image image) {
    // Mild global contrast around mid-grey (factor 1.15).
    const factor = 1.15;
    final out = img.Image(width: image.width, height: image.height);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        out.setPixelRgb(
          x,
          y,
          _contrast(p.r.toInt(), factor),
          _contrast(p.g.toInt(), factor),
          _contrast(p.b.toInt(), factor),
        );
      }
    }
    return out;
  }

  img.Image _blackWhite(img.Image image) {
    final w = image.width, h = image.height;
    final gray = List<int>.filled(w * h, 0);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        gray[y * w + x] = _luma(p.r, p.g, p.b);
      }
    }
    // Window scaled to image size (~1/40 of the long edge, odd, 15..51).
    final longEdge = w > h ? w : h;
    var window = (longEdge / 40).round();
    if (window.isEven) window += 1;
    if (window < 15) window = 15;
    if (window > 51) window = 51;
    final bin = _binarizer.sauvola(gray, w, h, window: window);

    final out = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final v = bin[y * w + x];
        out.setPixelRgb(x, y, v, v, v);
      }
    }
    return out;
  }

  // --- helpers -------------------------------------------------------------

  /// Clamp an int to 0..255 without `clamp` (whose static return type is num).
  int _byte(num v) {
    final i = v.round();
    if (i < 0) return 0;
    if (i > 255) return 255;
    return i;
  }

  int _luma(num r, num g, num b) => _byte(0.299 * r + 0.587 * g + 0.114 * b);

  /// Bilinear sample of [src] at fractional (fx, fy), clamped to edges.
  List<int> _bilinear(img.Image src, double fx, double fy) {
    final maxX = src.width - 1;
    final maxY = src.height - 1;
    var x = fx;
    if (x < 0) x = 0;
    if (x > maxX) x = maxX.toDouble();
    var y = fy;
    if (y < 0) y = 0;
    if (y > maxY) y = maxY.toDouble();

    final x0 = x.floor();
    final y0 = y.floor();
    final x1 = x0 + 1 > maxX ? maxX : x0 + 1;
    final y1 = y0 + 1 > maxY ? maxY : y0 + 1;
    final dx = x - x0;
    final dy = y - y0;

    final p00 = src.getPixel(x0, y0);
    final p10 = src.getPixel(x1, y0);
    final p01 = src.getPixel(x0, y1);
    final p11 = src.getPixel(x1, y1);

    int lerp(num a, num b, num c, num d) {
      final top = a + (b - a) * dx;
      final bot = c + (d - c) * dx;
      return _byte(top + (bot - top) * dy);
    }

    return [
      lerp(p00.r, p10.r, p01.r, p11.r),
      lerp(p00.g, p10.g, p01.g, p11.g),
      lerp(p00.b, p10.b, p01.b, p11.b),
    ];
  }

  int _stretch(int v, int lo, int hi) {
    if (hi <= lo) return v;
    return _byte(((v - lo) / (hi - lo)) * 255);
  }

  int _contrast(int v, double factor) => _byte(((v - 128) * factor) + 128);

  /// Approximate per-channel percentile value via a 256-bin histogram.
  int _percentile(img.Image image, int channel, double p) {
    final hist = List<int>.filled(256, 0);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final px = image.getPixel(x, y);
        final v = channel == 0
            ? px.r.toInt()
            : channel == 1
                ? px.g.toInt()
                : px.b.toInt();
        hist[v < 0 ? 0 : (v > 255 ? 255 : v)]++;
      }
    }
    final total = image.width * image.height;
    final target = (total * p).round();
    var cum = 0;
    for (var i = 0; i < 256; i++) {
      cum += hist[i];
      if (cum >= target) return i;
    }
    return 255;
  }
}
