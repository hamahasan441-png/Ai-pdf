import 'dart:ui' show Offset, Size, TextDirection;

import 'package:flutter/painting.dart';

/// Measures text dimensions for accurate auto-fit and bounding-box computation.
///
/// The existing auto-fit (`EditorFieldInputService.fitTextSize`) uses a rough
/// character-count heuristic (advance = 0.55 × size). This service provides
/// EXACT measurement using Flutter's TextPainter — giving pixel-accurate width
/// and height for any text + style combination.
///
/// ### Usage
/// ```dart
/// final service = TextMeasurementService();
/// final size = service.measure(
///   text: 'Muhammad Ali Al-Kurdi',
///   fontSize: 14.0,
///   bold: true,
///   maxWidth: 200.0,
/// );
/// // size.width = exact pixel width needed
/// ```
class TextMeasurementService {
  const TextMeasurementService();

  /// Measure the rendered size of [text] with the given style parameters.
  ///
  /// Returns the laid-out Size (width × height) in logical pixels.
  /// [maxWidth] constrains wrapping (use double.infinity for single-line).
  Size measure({
    required String text,
    required double fontSize,
    bool bold = false,
    bool italic = false,
    String? fontFamily,
    double lineHeight = 1.0,
    double charSpacing = 0.0,
    double maxWidth = double.infinity,
    TextDirection direction = TextDirection.ltr,
  }) {
    if (text.isEmpty) return Size.zero;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
          fontStyle: italic ? FontStyle.italic : FontStyle.normal,
          fontFamily: fontFamily,
          height: lineHeight,
          letterSpacing: charSpacing,
        ),
      ),
      textDirection: direction,
      maxLines: maxWidth == double.infinity ? 1 : null,
    )..layout(maxWidth: maxWidth);

    final result = Size(tp.width, tp.height);
    tp.dispose();
    return result;
  }

  /// Compute the font size needed to fit [text] within [availableWidth].
  /// Returns the largest fontSize ≤ [maxFontSize] that doesn't exceed the width.
  double fitFontSize({
    required String text,
    required double availableWidth,
    double maxFontSize = 24.0,
    double minFontSize = 6.0,
    bool bold = false,
    String? fontFamily,
  }) {
    if (text.isEmpty || availableWidth <= 0) return maxFontSize;

    // Binary search for the best size.
    double lo = minFontSize;
    double hi = maxFontSize;
    double best = minFontSize;

    for (int i = 0; i < 10; i++) {
      final mid = (lo + hi) / 2;
      final size = measure(text: text, fontSize: mid, bold: bold, fontFamily: fontFamily);
      if (size.width <= availableWidth) {
        best = mid;
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return best;
  }

  /// Compute the number of lines [text] would occupy at [fontSize] within [maxWidth].
  int lineCount({
    required String text,
    required double fontSize,
    required double maxWidth,
    bool bold = false,
    double lineHeight = 1.0,
  }) {
    if (text.isEmpty || maxWidth <= 0) return 0;

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
          height: lineHeight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    final lines = tp.computeLineMetrics().length;
    tp.dispose();
    return lines;
  }
}
