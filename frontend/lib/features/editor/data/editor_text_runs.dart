import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/rtl_detection_service.dart';

/// How a text box lays out on a page of a given size. The canvas, the inline
/// editor, the page renderer and the PDF export all use this, so a box wraps,
/// aligns and spaces its lines the same everywhere.
class AnnotationTextLayout {
  /// Base style (runs override parts of it).
  final TextStyle style;
  final TextDirection direction;

  /// [TextAnnotation.textAlign], except that left-aligned RTL text is
  /// right-aligned.
  final TextAlign align;

  /// The box is exactly [maxWidth] wide when [TextAnnotation.width] is set
  /// ([minWidth] == [maxWidth]); otherwise it is as wide as its text, up to
  /// the right edge of the page.
  final double minWidth;
  final double maxWidth;

  const AnnotationTextLayout._(this.style, this.direction, this.align, this.minWidth, this.maxWidth);

  static const _rtl = RtlDetectionService();

  factory AnnotationTextLayout.of(TextAnnotation t, Size page) {
    final direction = t.textDirection ?? (_rtl.isRtl(t.text) ? TextDirection.rtl : TextDirection.ltr);
    final align = t.textAlign == TextAlign.left && direction == TextDirection.rtl ? TextAlign.right : t.textAlign;
    final room = (page.width * (1 - t.pos.dx)).clamp(1.0, page.width > 1 ? page.width : 1.0);
    final fixed = t.width;
    final max = fixed != null && fixed > 0 ? (fixed * page.width).clamp(1.0, room) : room;
    return AnnotationTextLayout._(
      TextStyle(
        color: t.color,
        fontSize: t.size * page.height,
        fontWeight: t.bold ? FontWeight.w700 : FontWeight.w400,
        fontStyle: t.italic ? FontStyle.italic : FontStyle.normal,
        decoration: t.underline ? TextDecoration.underline : TextDecoration.none,
        decorationColor: t.color,
        fontFamily: t.fontFamily,
        height: t.lineHeight > 0 && t.lineHeight != 1.0 ? t.lineHeight : null,
        letterSpacing: t.charSpacing != 0 ? t.charSpacing : null,
      ),
      direction,
      align,
      fixed != null && fixed > 0 ? max : 0,
      max,
    );
  }

  /// A laid-out painter for [t].
  TextPainter painter(TextAnnotation t) => TextPainter(
        text: buildAnnotationTextSpan(t, style),
        textDirection: direction,
        textAlign: align,
      )..layout(minWidth: minWidth, maxWidth: maxWidth);
}

/// Build the [TextSpan] for a text annotation, honouring multi-run rich text
/// when [TextAnnotation.runs] is set.
///
/// Shared by the on-screen painter, the rasterized (RTL / export) renderer, and
/// the inline editor so every surface renders identical rich text. Each run
/// only overrides the fields it sets; null fields inherit [base].
TextSpan buildAnnotationTextSpan(TextAnnotation t, TextStyle base) {
  final runs = t.runs;
  if (runs == null || runs.isEmpty) {
    return TextSpan(text: t.text, style: base);
  }
  return TextSpan(
    style: base,
    children: [
      for (final r in runs)
        TextSpan(
          text: r.text,
          style: base.copyWith(
            fontWeight: r.bold == null
                ? null
                : (r.bold! ? FontWeight.w700 : FontWeight.w400),
            fontStyle: r.italic == null
                ? null
                : (r.italic! ? FontStyle.italic : FontStyle.normal),
            decoration: r.underline == null
                ? null
                : (r.underline! ? TextDecoration.underline : TextDecoration.none),
            color: r.color,
            fontFamily: r.fontFamily,
            fontSize: r.sizeScale == null
                ? null
                : (base.fontSize ?? 14.0) * r.sizeScale!,
          ),
        ),
    ],
  );
}
