import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Small factory helpers for common editor annotations.
class EditorAnnotationFactoryService {
  const EditorAnnotationFactoryService();

  TextAnnotation textAt(
    Offset pos,
    double size,
    String text, {
    Color color = Colors.black,
    bool bold = false,
    bool italic = false,
    bool underline = false,
    String? fontFamily,
  }) {
    return TextAnnotation(pos, text, color, size, bold, italic, underline, fontFamily);
  }

  TextAnnotation markAt(Offset pos, String glyph, Color color) {
    return TextAnnotation(pos, glyph, color, 0.04, false);
  }

  TextAnnotation signatureDateAt(Offset pos, String text, Color color, double size, bool bold) {
    return TextAnnotation(pos, text, color, size, bold);
  }

  TextAnnotation typedSignature(String text) {
    return TextAnnotation(
      const Offset(0.4, 0.68),
      text,
      Colors.black,
      0.045,
      false,
      true,
      false,
      'serif',
    );
  }
}
