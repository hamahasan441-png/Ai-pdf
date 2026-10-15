import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/pdf_unicode_fonts.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// How sure we are about the font used for a replacement box.
enum FontMatchKind {
  /// The PDF BaseFont, after removing a subset tag, is exactly a face this
  /// editor ships. This is a name match, not a byte-identical embedded font.
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

  /// PDF subset prefixes look like `ABCDEF+`. They are not part of the face.
  static final RegExp subsetPrefix = RegExp(r'^[A-Z]{6}\+');

  /// Faces whose file names the editor knows. A substring such as
  /// "NotoSansArabic" inside a different face name is not an exact match.
  static const Map<String, String> exactFaces = {
    'notosans-regular': 'NotoSans',
    'notosans-bold': 'NotoSans',
    'notosansarabic-regular': 'NotoSansArabic',
    'notosansarabic-bold': 'NotoSansArabic',
    'vazirmatn-regular': 'Vazirmatn',
    'vazirmatn-bold': 'Vazirmatn',
    'notosanshebrew-regular': 'NotoSansHebrew',
    'notosanshebrew-bold': 'NotoSansHebrew',
  };

  static String normalizeFontName(String? raw) {
    if (raw == null) return '';
    var name = raw.trim();
    if (name.startsWith('/')) name = name.substring(1);
    name = name.replaceFirst(subsetPrefix, '');
    return name;
  }

  RecognizedTextStyle match(PdfTextElement word, {double pageHeightPt = 0}) {
    final source = word.fontName;
    final normalizedName = normalizeFontName(source);
    final lower = normalizedName.toLowerCase();
    final script = PdfUnicodeFonts.scriptOf(word.text);
    final rtl = script == EmbeddedScript.arabic || script == EmbeddedScript.hebrew;

    String? family;
    var kind = FontMatchKind.unknown;
    final exact = exactFaces[lower];
    if (exact != null) {
      family = exact;
      kind = FontMatchKind.exactFamily;
    } else if (lower.contains('vazir')) {
      family = 'Vazirmatn';
      kind = FontMatchKind.namedSubstitute;
    } else if (lower.contains('notosansarabic') || lower.contains('notonaskh')) {
      family = 'NotoSansArabic';
      kind = FontMatchKind.namedSubstitute;
    } else if (lower.contains('courier') || lower.contains('mono') || lower.contains('consol')) {
      family = 'monospace';
      kind = FontMatchKind.namedSubstitute;
    } else if (lower.contains('liberation') && lower.contains('sans')) {
      // Liberation Sans is not a serif. We have no metric-compatible file.
      kind = FontMatchKind.unknown;
    } else if (lower.contains('times') ||
        lower.contains('georgia') ||
        lower.contains('liberation') ||
        lower.contains('nimbusrom')) {
      family = 'serif';
      kind = FontMatchKind.namedSubstitute;
    } else if (rtl) {
      family = script == EmbeddedScript.hebrew ? 'NotoSansHebrew' : 'NotoSansArabic';
      kind = FontMatchKind.namedSubstitute;
    } else if (word.source == TextGeometrySource.ocr && lower.isEmpty) {
      kind = FontMatchKind.unknown;
    }

    final bold = word.isBold || lower.contains('bold') || lower.contains('black');
    final italic = word.isItalic || lower.contains('italic') || lower.contains('oblique');

    final hasPoints = word.fontSize > 0 &&
        pageHeightPt > 0 &&
        word.fontSize.isFinite &&
        pageHeightPt.isFinite;
    // Point size is not clamped. A clamp here would silently change the
    // replacement box relative to the PDF. Estimates from the box height are
    // labelled [sizeIsEstimate] and are also left unclamped.
    final double normalized;
    if (hasPoints) {
      normalized = word.fontSize / pageHeightPt;
    } else if (word.rect.height.isFinite && word.rect.height > 0) {
      normalized = word.rect.height * 0.85;
    } else {
      normalized = 0;
    }

    return RecognizedTextStyle(
      sourceFontName: source,
      editorFamily: family,
      kind: kind,
      fontSizePt: word.fontSize > 0 && word.fontSize.isFinite ? word.fontSize : 0,
      normalizedSize: normalized,
      sizeIsEstimate: !hasPoints || word.source == TextGeometrySource.ocr,
      bold: bold,
      italic: italic,
      direction: rtl ? TextDirection.rtl : null,
    );
  }
}
