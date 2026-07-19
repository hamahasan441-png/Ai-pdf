import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/tools/models/filled_field.dart';

/// Creates editor annotations from smart-fill / workflow field results.
class EditorAnnotationApplyService {
  const EditorAnnotationApplyService();

  void applyFilledFieldsToLayer(PageLayer layer, List<FilledField> fields) {
    for (final f in fields) {
      if (f.isCheck) {
        layer.items.add(TextAnnotation(Offset(f.x, f.y), f.text, Colors.black, 0.03, true));
      } else if (f.isSignature) {
        layer.items.add(TextAnnotation(
          Offset(f.x, f.y),
          f.text,
          Colors.black,
          0.032,
          false,
          true,
          false,
          'serif',
        ));
      } else {
        layer.items.add(TextAnnotation(Offset(f.x, f.y), f.text, Colors.black, 0.024, false));
      }
    }
  }
}
