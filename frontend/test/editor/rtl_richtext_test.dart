import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/data/editor_text_runs.dart';
import 'package:ai_pdf/features/editor/data/pdf_unicode_fonts.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

void main() {
  group('PdfUnicodeFonts script classification (Phase 4)', () {
    test('detects Arabic, Hebrew, and other scripts', () {
      expect(PdfUnicodeFonts.scriptOf('مرحبا'), EmbeddedScript.arabic);
      expect(PdfUnicodeFonts.scriptOf('سڵاو'), EmbeddedScript.arabic); // Kurdish (Arabic script)
      expect(PdfUnicodeFonts.scriptOf('שלום'), EmbeddedScript.hebrew);
      expect(PdfUnicodeFonts.scriptOf('Hello'), EmbeddedScript.other);
      expect(PdfUnicodeFonts.scriptOf('123 مرحبا'), EmbeddedScript.arabic);
    });

    test('pick returns null when no fonts are loaded (raster fallback)', () {
      final fonts = PdfUnicodeFonts(); // load() not called → nothing bundled
      final arabic = TextAnnotation(const Offset(0, 0), 'مرحبا', Colors.black, 0.05, false);
      expect(fonts.pick(arabic), isNull);
      expect(fonts.hasRtl, isFalse);
    });
  });

  group('Rich text runs span builder (Phase 5)', () {
    test('single-style annotation yields a plain span', () {
      final t = TextAnnotation(const Offset(0, 0), 'plain', Colors.black, 0.05, false);
      final span = buildAnnotationTextSpan(t, const TextStyle(fontSize: 20));
      expect(span.text, 'plain');
      expect(span.children, isNull);
    });

    test('multi-run annotation yields per-run styled children', () {
      final t = TextAnnotation(
        const Offset(0, 0),
        'Hello world',
        Colors.black,
        0.05,
        false,
        runs: const [
          TextRun('Hello ', bold: true, color: Colors.red),
          TextRun('world', italic: true, sizeScale: 2.0),
        ],
      );
      final span = buildAnnotationTextSpan(t, const TextStyle(fontSize: 20));
      expect(span.children, hasLength(2));
      final first = span.children![0] as TextSpan;
      final second = span.children![1] as TextSpan;
      expect(first.style!.fontWeight, FontWeight.w700);
      expect(first.style!.color, Colors.red);
      expect(second.style!.fontStyle, FontStyle.italic);
      expect(second.style!.fontSize, 40.0); // 20 * 2.0
    });
  });

  group('Rich text serialization (Phase 5)', () {
    test('runs round-trip through JSON', () {
      final t = TextAnnotation(
        const Offset(0.1, 0.2),
        'Hello world',
        Colors.black,
        0.05,
        false,
        runs: const [
          TextRun('Hello ', bold: true, color: Colors.red),
          TextRun('world', italic: true, underline: true, sizeScale: 1.5),
        ],
      );
      final restored = annotationFromJson(annotationToJson(t))! as TextAnnotation;
      expect(restored.runs, isNotNull);
      expect(restored.runs, hasLength(2));
      expect(restored.runs![0].bold, isTrue);
      expect(restored.runs![0].color!.value, Colors.red.value);
      expect(restored.runs![1].italic, isTrue);
      expect(restored.runs![1].underline, isTrue);
      expect(restored.runs![1].sizeScale, 1.5);
    });

    test('plain text has null runs after round-trip', () {
      final t = TextAnnotation(const Offset(0, 0), 'plain', Colors.black, 0.05, false);
      final restored = annotationFromJson(annotationToJson(t))! as TextAnnotation;
      expect(restored.runs, isNull);
    });
  });
}
