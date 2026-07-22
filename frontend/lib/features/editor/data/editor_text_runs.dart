import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

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
