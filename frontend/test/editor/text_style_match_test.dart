import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/core/services/ocr_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/data/editor_existing_text_service.dart';
import 'package:ai_pdf/features/editor/data/pdf_content_text_extractor.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/data/text_style_match.dart';

void main() {
  const matcher = TextStyleMatcher();

  test('an embedded Noto name is exact, and the size is real points', () {
    final word = PdfTextElement(
      text: 'کوردی',
      rect: const Rect.fromLTWH(0.1, 0.2, 0.2, 0.03),
      fontSize: 14,
      fontName: 'NotoSansArabic-Bold',
      isBold: true,
    );
    final style = matcher.match(word, pageHeightPt: 792);
    expect(style.kind, FontMatchKind.exactFamily);
    expect(style.editorFamily, 'NotoSansArabic');
    expect(style.bold, isTrue);
    expect(style.sizeIsEstimate, isFalse);
    expect(style.normalizedSize, closeTo(14 / 792, 0.0001));
    expect(style.direction, TextDirection.rtl);
  });

  test('Times-Bold is a substitute, not the original font', () {
    final word = PdfTextElement(
      text: 'Hello',
      rect: const Rect.fromLTWH(0.1, 0.2, 0.2, 0.02),
      fontSize: 12,
      fontName: 'Times-Bold',
    );
    final style = matcher.match(word, pageHeightPt: 792);
    expect(style.kind, FontMatchKind.namedSubstitute);
    expect(style.editorFamily, 'serif');
    expect(style.bold, isTrue);
    expect(style.direction, isNull);
  });

  test('without a page height the size is marked as an estimate', () {
    final word = PdfTextElement(
      text: 'ABC',
      rect: const Rect.fromLTWH(0.1, 0.2, 0.3, 0.04),
      fontSize: 0,
    );
    final style = matcher.match(word);
    expect(style.sizeIsEstimate, isTrue);
    expect(style.kind, FontMatchKind.unknown);
  });

  test('a Kurdish OCR line uses an Arabic-script font and stays RTL', () {
    final draft = const EditorExistingTextService().draftForLine(
      const OcrLine('کوردستان', 0.1, 0.2, 0.4, 0.05),
    );
    expect(draft.textBox.fontFamily, 'NotoSansArabic');
    expect(draft.textBox.textDirection, TextDirection.rtl);
    expect(draft.textBox.text, 'کوردستان');
  });

  test('selected words keep the first size and do not average a second size', () {
    final words = [
      PdfTextElement(
        text: 'PDF',
        rect: const Rect.fromLTWH(0.1, 0.1, 0.1, 0.02),
        fontSize: 18,
        fontName: 'NotoSansArabic-Regular',
      ),
      PdfTextElement(
        text: 'و',
        rect: const Rect.fromLTWH(0.22, 0.1, 0.04, 0.015),
        fontSize: 10,
      ),
    ];
    final draft = const EditorExistingTextService().draftForWords(words, pageHeightPt: 800);
    expect(draft.textBox.text, 'PDF و');
    expect(draft.textBox.size, closeTo(18 / 800, 0.0001));
    expect(draft.textBox.fontFamily, 'NotoSansArabic');
    expect(draft.whiteout.type, ShapeType.whiteout);
  });

  test('a subset prefix still names the exact bundled face', () {
    final word = PdfTextElement(
      text: 'کوردی',
      rect: const Rect.fromLTWH(0.1, 0.2, 0.2, 0.03),
      fontSize: 14,
      fontName: 'ABCDEF+NotoSansArabic-Bold',
    );
    final style = matcher.match(word, pageHeightPt: 792);
    expect(style.kind, FontMatchKind.exactFamily);
    expect(style.editorFamily, 'NotoSansArabic');
  });

  test('a name that merely contains Noto Sans Arabic is not an exact face', () {
    final word = PdfTextElement(
      text: 'کوردی',
      rect: const Rect.fromLTWH(0.1, 0.2, 0.2, 0.03),
      fontSize: 14,
      fontName: 'MyNotoSansArabicClone',
    );
    final style = matcher.match(word, pageHeightPt: 792);
    expect(style.kind, FontMatchKind.namedSubstitute);
    expect(style.editorFamily, 'NotoSansArabic');
  });

  test('LiberationMono is monospace, not serif', () {
    final word = PdfTextElement(
      text: 'code',
      rect: const Rect.fromLTWH(0.1, 0.2, 0.2, 0.02),
      fontSize: 10,
      fontName: 'LiberationMono',
    );
    final style = matcher.match(word, pageHeightPt: 792);
    expect(style.kind, FontMatchKind.namedSubstitute);
    expect(style.editorFamily, 'monospace');
  });

  test('a large point size is not silently clamped', () {
    final word = PdfTextElement(
      text: 'Title',
      rect: const Rect.fromLTWH(0.1, 0.1, 0.5, 0.3),
      fontSize: 200,
      fontName: 'Times-Roman',
    );
    final style = matcher.match(word, pageHeightPt: 400);
    expect(style.sizeIsEstimate, isFalse);
    expect(style.normalizedSize, closeTo(0.5, 0.0001));
    expect(style.fontSizePt, 200);
  });

  test('different sizes in one selection stay separate runs', () {
    final words = [
      PdfTextElement(
        text: 'PDF',
        rect: const Rect.fromLTWH(0.1, 0.1, 0.1, 0.02),
        fontSize: 18,
        fontName: 'NotoSansArabic-Regular',
      ),
      PdfTextElement(
        text: 'و',
        rect: const Rect.fromLTWH(0.22, 0.1, 0.04, 0.015),
        fontSize: 10,
      ),
    ];
    final draft = const EditorExistingTextService().draftForWords(words, pageHeightPt: 800);
    expect(draft.textBox.text, 'PDF و');
    expect(draft.textBox.runs, isNotNull);
    expect(draft.textBox.runs!.map((r) => r.text).join(), 'PDF و');
    final scaled = draft.textBox.runs!.last.sizeScale;
    expect(scaled, isNotNull);
    expect(scaled!, closeTo(10 / 18, 0.02));
  });

  test('missing fontSize in JSON is unknown, not a fake 12pt', () {
    final parsed = const TextLayerExtractionService().parseFromJson([
      {'text': 'Hi', 'x': 0.1, 'y': 0.1, 'w': 0.2, 'h': 0.02},
    ]);
    expect(parsed.single.fontSize, 0);
    expect(parsed.single.source, TextGeometrySource.native);
  });

  test('a tiny PDF reports the BaseFont name and point size', () {
    final pdf = _miniPdf();
    final pages = const PdfContentTextExtractor().extract(pdf);
    expect(pages[0], isNotNull);
    final word = pages[0]!.single;
    expect(word.text, 'Hello');
    expect(word.fontName, 'Times-Bold');
    expect(word.fontSize, 18);
    expect(word.isBold, isTrue);
  });
}

Uint8List _miniPdf() {
  const body = '''%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>
endobj
4 0 obj
<< /Length 36 >>
stream
BT
/F1 18 Tf
10 40 Td
(Hello) Tj
ET
endstream
endobj
5 0 obj
<< /Type /Font /Subtype /Type1 /BaseFont /Times-Bold >>
endobj
''';
  return Uint8List.fromList(body.codeUnits);
}
