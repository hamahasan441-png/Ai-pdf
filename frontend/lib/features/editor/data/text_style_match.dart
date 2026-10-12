import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/pdf_unicode_fonts.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// How sure we are about the font used for a replacement box.
enum FontMatchKind {
  /// The PDF font resource name is one of the families this editor can embed.
  exactFamily,

  /// A different installed family was chosen. It is not the original font.
  namedSubstitute,

  /// No trustworthy family. Size may still come from the PDF.
  unknown,
}

/// Style copied from a PDF text run, for an overlay replacement.
///
/// This is not a claim that the original text object was edited.
class RecognizedTextStyle {
  final String? sourceFontName;
  final String? editorFamily;
  final FontMatchKind kind;
  final double fontSizePt;
  final double normalizedSize;
  final bool sizeIsEstimate;
  final bool bold;
  final bool italic;
  final TextDirection? direction;

  const RecognizedTextStyle({
    required this.sourceFontName,
    required this.editorFamily,
    required this.kind,
    required this.fontSizePt,
    required this.normalizedSize,
    required this.sizeIsEstimate,
    required this.bold,
    required this.italic,
    required this.direction,
  });
}

class TextStyleMatcher {
  const TextStyleMatcher();

  RecognizedTextStyle match(PdfTextElement word, {double pageHeightPt = 0}) {
    final source = word.fontName;
    final lower = (source ?? '').toLowerCase();
    final script = PdfUnicodeFonts.scriptOf(word.text);
    final rtl = script == EmbeddedScript.arabic || script == EmbeddedScript.hebrew;

    String? family;
    var kind = FontMatchKind.unknown;
    if (lower.contains('vazir')) {
      family = 'Vazirmatn';
      kind = FontMatchKind.exactFamily;
    } else if (lower.contains('notosansarabic') || lower.contains('notonaskh')) {
      family = 'NotoSansArabic';
      kind = FontMatchKind.exactFamily;
    } else if (lower.contains('times') ||
        lower.contains('georgia') ||
        lower.contains('liberation') ||
        lower.contains('nimbusrom')) {
      family = 'serif';
      kind = FontMatchKind.namedSubstitute;
    } else if (lower.contains('courier') || lower.contains('mono') || lower.contains('consol')) {
      family = 'monospace';
      kind = FontMatchKind.namedSubstitute;
    } else if (rtl) {
      family = script == EmbeddedScript.hebrew ? 'NotoSansHebrew' : 'NotoSansArabic';
      kind = FontMatchKind.namedSubstitute;
    }

    final bold = word.isBold || lower.contains('bold') || lower.contains('black');
    final italic = word.isItalic || lower.contains('italic') || lower.contains('oblique');

    final hasPoints = word.fontSize > 1 && pageHeightPt > 1;
    final normalized = hasPoints
        ? (word.fontSize / pageHeightPt).clamp(0.008, 0.2).toDouble()
        : (word.rect.height * 0.85).clamp(0.012, 0.08).toDouble();

    return RecognizedTextStyle(
      sourceFontName: source,
      editorFamily: family,
      kind: kind,
      fontSizePt: hasPoints ? word.fontSize : normalized * (pageHeightPt > 1 ? pageHeightPt : 0),
      normalizedSize: normalized,
      sizeIsEstimate: !hasPoints,
      bold: bold,
      italic: italic,
      direction: rtl ? TextDirection.rtl : null,
    );
  }
}
