import 'package:flutter/material.dart';

import 'package:ai_pdf/core/services/ocr_service.dart';
import 'package:ai_pdf/features/editor/data/pdf_unicode_fonts.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/data/text_style_match.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

class ExistingLineEditDraft {
  final ShapeAnnotation whiteout;
  final TextAnnotation textBox;

  const ExistingLineEditDraft({required this.whiteout, required this.textBox});
}

/// Overlay replacement. This does not rewrite the original PDF text object.
/// It places a whiteout shape and a new text box that copies the styles we
/// can actually read. A missing font is a substitute, not the original face.
class EditorExistingTextService {
  const EditorExistingTextService();

  ExistingLineEditDraft draftForLine(OcrLine line) {
    final size = (line.h * 0.72).clamp(0.012, 0.08).toDouble();
    final rtl = PdfUnicodeFonts.scriptOf(line.text) == EmbeddedScript.arabic ||
        PdfUnicodeFonts.scriptOf(line.text) == EmbeddedScript.hebrew;
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
        fontFamily: rtl
            ? (PdfUnicodeFonts.scriptOf(line.text) == EmbeddedScript.hebrew
                ? 'NotoSansHebrew'
                : 'NotoSansArabic')
            : null,
        textDirection: rtl ? TextDirection.rtl : null,
      ),
    );
  }

  /// Cover the selected PDF words and open one replacement box.
  ///
  /// Style comes from the first word. Later words with a different size are
  /// not averaged, because one box cannot keep several sizes.
  ExistingLineEditDraft draftForWords(
    List<PdfTextElement> words, {
    double pageHeightPt = 0,
  }) {
    final first = words.first;
    final style = const TextStyleMatcher().match(first, pageHeightPt: pageHeightPt);
    var left = first.rect.left;
    var top = first.rect.top;
    var right = first.rect.right;
    var bottom = first.rect.bottom;
    final buffer = StringBuffer();
    for (final word in words) {
      if (buffer.isNotEmpty) buffer.write(' ');
      buffer.write(word.text);
      if (word.rect.left < left) left = word.rect.left;
      if (word.rect.top < top) top = word.rect.top;
      if (word.rect.right > right) right = word.rect.right;
      if (word.rect.bottom > bottom) bottom = word.rect.bottom;
    }
    return ExistingLineEditDraft(
      whiteout: ShapeAnnotation(
        ShapeType.whiteout,
        Offset(left, top),
        Offset(right, bottom),
        Colors.white,
        1,
      ),
      textBox: TextAnnotation(
        Offset(left, top),
        buffer.toString(),
        Colors.black,
        style.normalizedSize,
        style.bold,
        italic: style.italic,
        fontFamily: style.editorFamily,
        textDirection: style.direction,
        textAlign: style.direction == TextDirection.rtl ? TextAlign.right : TextAlign.left,
      ),
    );
  }
}
