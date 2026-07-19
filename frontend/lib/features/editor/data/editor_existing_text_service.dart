import 'package:flutter/material.dart';

import 'package:ai_pdf/core/services/ocr_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

class ExistingLineEditDraft {
  final ShapeAnnotation whiteout;
  final TextAnnotation textBox;

  const ExistingLineEditDraft({required this.whiteout, required this.textBox});
}

/// Helpers for the editor's OCR-based existing-text editing flow.
class EditorExistingTextService {
  const EditorExistingTextService();

  ExistingLineEditDraft draftForLine(OcrLine line) {
    final size = (line.h * 0.72).clamp(0.012, 0.08).toDouble();
    return ExistingLineEditDraft(
      whiteout: ShapeAnnotation(
        ShapeType.whiteout,
        Offset(line.x, line.y),
        Offset(line.x + line.w, line.y + line.h),
        Colors.white,
        1,
      ),
      textBox: TextAnnotation(
        Offset(line.x, line.y + line.h * 0.1),
        line.text.trim(),
        Colors.black,
        size,
        false,
      ),
    );
  }
}
