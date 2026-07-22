import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/blank_page_detection_service.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

PdfTextElement _el(String text) =>
    PdfTextElement(text: text, rect: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.05), fontSize: 12);

void main() {
  const svc = BlankPageDetectionService();

  group('BlankPageDetectionService (Phase 26)', () {
    test('flags whitespace-only and empty pages, keeps pages with text', () {
      final pages = <int, List<PdfTextElement>>{
        0: [_el('   ')], // whitespace only
        1: [_el('Hello world')], // real text
        2: <PdfTextElement>[], // no elements
      };
      expect(svc.blankPages(pages), [0, 2]);
    });

    test('ink coverage rescues an image-only (scanned) page', () {
      final pages = <int, List<PdfTextElement>>{
        0: <PdfTextElement>[], // no text layer
        1: [_el('text')],
      };
      // Page 0 has heavy ink (a scan) => NOT blank.
      final blanks = svc.blankPages(pages, inkCoverage: {0: 0.42});
      expect(blanks, isEmpty);
    });

    test('low ink coverage below threshold is still blank', () {
      final pages = <int, List<PdfTextElement>>{0: <PdfTextElement>[]};
      final blanks = svc.blankPages(pages, inkCoverage: {0: 0.001});
      expect(blanks, [0]);
    });

    test('analyze reports per-page detail', () {
      final pages = <int, List<PdfTextElement>>{
        0: [_el('ab')],
        1: [_el(' ')],
      };
      final results = svc.analyze(pages);
      expect(results.length, 2);
      expect(results[0].visibleChars, 2);
      expect(results[0].isBlank, isFalse);
      expect(results[1].visibleChars, 0);
      expect(results[1].isBlank, isTrue);
    });

    test('minChars threshold is configurable', () {
      final pages = <int, List<PdfTextElement>>{
        0: [_el('x')], // 1 visible char
      };
      // Default minChars=2 => "x" counts as blank-ish.
      expect(svc.blankPages(pages), [0]);
      // Raise tolerance so a single char is enough content.
      expect(
        svc.blankPages(pages, config: const BlankPageConfig(minChars: 1)),
        isEmpty,
      );
    });

    test('page set is the union of text and ink-coverage keys, sorted', () {
      final results = svc.analyze(
        <int, List<PdfTextElement>>{0: [_el('hi')]},
        inkCoverage: {2: 0.0},
      );
      expect(results.map((r) => r.pageIndex), [0, 2]);
      expect(results[1].isBlank, isTrue); // page 2: no text, ~zero ink
    });
  });
}
