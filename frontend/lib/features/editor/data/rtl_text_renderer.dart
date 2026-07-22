import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/rtl_detection_service.dart';

/// Enhanced text renderer with automatic RTL detection.
///
/// Wraps the existing AnnotationDraw.text() logic with auto-direction detection
/// so Arabic, Kurdish, Persian, and Hebrew text renders correctly without the
/// user manually setting textDirection on every annotation.
///
/// ### How it works
/// 1. If the annotation has an explicit [textDirection], use it (user override).
/// 2. Otherwise, detect from the text content using [RtlDetectionService].
/// 3. Pass the resolved direction to [TextPainter].
///
/// This does NOT modify the annotation itself (detection is runtime-only).
class RtlTextRenderer {
  static const RtlDetectionService _rtlService = RtlDetectionService();

  const RtlTextRenderer();

  /// Paint a text annotation with auto-RTL detection.
  void paint(Canvas canvas, Size size, TextAnnotation t) {
    if (t.text.isEmpty) return;

    // Resolve text direction.
    final direction = t.textDirection ?? _detectDirection(t.text);

    // Resolve text alignment for RTL (if not explicitly set by user).
    final align = t.textAlign == TextAlign.left && direction == TextDirection.rtl
        ? TextAlign.right
        : t.textAlign;

    final tp = TextPainter(
      text: TextSpan(
        text: t.text,
        style: TextStyle(
          color: t.color,
          fontSize: t.size * size.height,
          fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
          fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
          decoration: t.underline ? TextDecoration.underline : TextDecoration.none,
          decorationColor: t.color,
          fontFamily: t.fontFamily,
          height: t.lineHeight,
          letterSpacing: t.charSpacing,
        ),
      ),
      textDirection: direction,
      textAlign: align,
    )..layout(maxWidth: size.width * (1 - t.pos.dx));

    tp.paint(canvas, Offset(t.pos.dx * size.width, t.pos.dy * size.height));
  }

  /// Detect text direction from content.
  TextDirection _detectDirection(String text) {
    return _rtlService.isRtl(text) ? TextDirection.rtl : TextDirection.ltr;
  }
}
