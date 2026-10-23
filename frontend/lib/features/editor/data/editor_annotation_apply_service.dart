import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/tools/models/filled_field.dart';

/// Creates editor annotations from smart-fill / workflow field results.
class EditorAnnotationApplyService {
  const EditorAnnotationApplyService();

  /// The text marks that show [fields]; the caller adds them as one undo step.
  List<TextAnnotation> annotationsForFilledFields(List<FilledField> fields) {
    final out = <TextAnnotation>[];
    for (final f in fields) {
      if (f.isCheck) {
        out.add(TextAnnotation(Offset(f.x, f.y), f.text, Colors.black, 0.03, true));
      } else if (f.isSignature) {
        out.add(TextAnnotation(
          Offset(f.x, f.y),
          f.text,
          Colors.black,
          0.032,
          false,
          italic: true,
          underline: false,
          fontFamily: 'serif',
        ));
      } else {
        out.add(TextAnnotation(Offset(f.x, f.y), f.text, Colors.black, 0.024, false));
      }
    }
    return out;
  }
}
