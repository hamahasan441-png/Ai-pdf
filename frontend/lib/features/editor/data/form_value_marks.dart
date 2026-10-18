import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Marks that draw edited form values onto a page bitmap.
///
/// The source-preserving export writes values into the form itself. A page
/// saved as an image (the image-only export, or a page flattened because a
/// cover hides content) has no form any more, so the values the user typed
/// would be lost. Each edited field gets a white box over its widget (hiding
/// the old appearance the renderer drew) and its new value on top.
///
/// Keys are editor page indexes.
Map<int, List<EditorAnnotation>> formValueMarks({
  required AcroFormSnapshot form,
  required Map<String, Object> edits,
  required List<int> sourcePages,
  Map<int, int> quarterTurns = const {},
}) {
  final out = <int, List<EditorAnnotation>>{};
  if (edits.isEmpty || form.isEmpty) return out;
  for (var i = 0; i < sourcePages.length; i++) {
    final source = sourcePages[i];
    if (source < 0) continue;
    for (final f in form.fields) {
      final value = edits[f.name];
      if (value == null || !f.fillable) continue;
      for (final w in f.widgets) {
        if (w.pageIndex != source) continue;
        final r = form.rectOf(w, quarterTurns: quarterTurns[i] ?? 0);
        if (r.isEmpty) continue;
        final marks = out.putIfAbsent(i, () => []);
        marks.add(ShapeAnnotation(ShapeType.rect, r.topLeft, r.bottomRight, Colors.white, 0, true));
        final text = switch (f.kind) {
          AcroFieldKind.checkbox => value != 'Off' ? '✓' : '',
          AcroFieldKind.radio => value == w.onState ? '●' : '',
          _ => fieldDisplayText(f, value),
        };
        if (text.isEmpty) continue;
        final size = (r.height * (f.multiline ? 0.25 : 0.6)).clamp(0.006, 0.03).toDouble();
        marks.add(TextAnnotation(
          Offset(r.left + 0.002, r.top + (f.multiline ? 0.002 : (r.height - size * 1.2) / 2)),
          text,
          Colors.black,
          size,
          false,
        ));
      }
    }
  }
  return out;
}
