import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/document_search_service.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

PdfTextElement _el(String text, {double y = 0}) => PdfTextElement(
      text: text,
      rect: Rect.fromLTWH(0.1, y, 0.5, 0.05),
      fontSize: 12,
    );

void main() {
  const svc = DocumentSearchService();

  group('DocumentSearchService (Phase 12)', () {
    test('finds a term across multiple pages in reading order', () {
      final pages = <int, List<PdfTextElement>>{
        0: [_el('the invoice total'), _el('due date')],
        1: [_el('invoice number 42')],
      };
      final matches = svc.search(pages, 'invoice');
      expect(matches.length, 2);
      expect(matches[0].pageIndex, 0);
      expect(matches[0].elementIndex, 0);
      expect(matches[1].pageIndex, 1);
    });

    test('finds multiple hits within a single element', () {
      final pages = {
        0: [_el('na na na batman')],
      };
      final matches = svc.search(pages, 'na');
      expect(matches.length, 3);
      expect(matches[0].start, 0);
      expect(matches[1].start, 3);
      expect(matches[2].start, 6);
    });

    test('is case-insensitive by default and preserves original-case text', () {
      final pages = {
        0: [_el('Invoice INVOICE invoice')],
      };
      final matches = svc.search(pages, 'invoice');
      expect(matches.length, 3);
      expect(matches[0].text, 'Invoice');
      expect(matches[1].text, 'INVOICE');
    });

    test('case-sensitive option only matches exact case', () {
      final pages = {
        0: [_el('Invoice INVOICE invoice')],
      };
      final matches = svc.search(pages, 'invoice',
          options: const SearchOptions(caseSensitive: true));
      expect(matches.length, 1);
      expect(matches.single.text, 'invoice');
    });

    test('whole-word option excludes substrings', () {
      final pages = {
        0: [_el('cat category concatenate cat')],
      };
      final whole = svc.search(pages, 'cat',
          options: const SearchOptions(wholeWord: true));
      expect(whole.length, 2); // the two standalone "cat" words
      final loose = svc.search(pages, 'cat');
      expect(loose.length, 4); // cat, cat(egory), (con)cat(enate), cat
    });

    test('empty / whitespace query yields nothing', () {
      final pages = {
        0: [_el('anything')],
      };
      expect(svc.search(pages, ''), isEmpty);
      expect(svc.search(pages, '   '), isEmpty);
      expect(svc.count(pages, 'x'), 0);
    });

    test('match rect equals the containing element rect', () {
      final el = _el('find me here', y: 0.3);
      final pages = {
        0: [el],
      };
      final m = svc.search(pages, 'me').single;
      expect(m.rect, el.rect);
    });

    test('next/previous navigation wraps around', () {
      expect(svc.nextIndex(-1, 3), 0);
      expect(svc.nextIndex(0, 3), 1);
      expect(svc.nextIndex(2, 3), 0); // wrap forward
      expect(svc.previousIndex(0, 3), 2); // wrap backward
      expect(svc.previousIndex(2, 3), 1);
      expect(svc.nextIndex(0, 0), -1); // no matches
      expect(svc.previousIndex(0, 0), -1);
    });
  });
}
