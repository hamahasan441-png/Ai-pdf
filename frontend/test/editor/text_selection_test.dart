import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/domain/services/text_selection_service.dart';

/// Helper: element on a line at [top], spanning [left]..[right] horizontally.
PdfTextElement _el(String text, double left, double top, {double w = 0.15}) =>
    PdfTextElement(
      text: text,
      rect: Rect.fromLTWH(left, top, w, 0.03),
      fontSize: 12,
    );

void main() {
  const svc = TextSelectionService();

  group('TextSelectionService (Phase 13)', () {
    // A 2-line layout:
    // line 1 (top 0.10): "Hello" "World"
    // line 2 (top 0.20): "Foo"   "Bar"
    final elements = [
      _el('Hello', 0.10, 0.10),
      _el('World', 0.30, 0.10),
      _el('Foo', 0.10, 0.20),
      _el('Bar', 0.30, 0.20),
    ];

    test('selecting within one line grabs the run in reading order', () {
      final r = svc.selectRange(
        elements,
        const Offset(0.12, 0.11), // inside "Hello"
        const Offset(0.32, 0.11), // inside "World"
      );
      expect(r.indices, [0, 1]);
      expect(r.text, 'Hello World');
      expect(r.rects.length, 2);
    });

    test('reversed drag direction yields the same forward selection', () {
      final r = svc.selectRange(
        elements,
        const Offset(0.32, 0.11), // start in "World"
        const Offset(0.12, 0.11), // end in "Hello"
      );
      expect(r.indices, [0, 1]);
      expect(r.text, 'Hello World');
    });

    test('cross-line selection inserts a newline between lines', () {
      final r = svc.selectRange(
        elements,
        const Offset(0.12, 0.11), // "Hello"
        const Offset(0.12, 0.21), // "Foo"
      );
      expect(r.indices, [0, 1, 2]);
      expect(r.text, 'Hello World\nFoo');
    });

    test('a point in a gap snaps to the nearest element', () {
      final r = svc.selectRange(
        elements,
        const Offset(0.0, 0.10), // left of "Hello" -> nearest is Hello
        const Offset(0.11, 0.10),
      );
      expect(r.indices, [0]);
      expect(r.text, 'Hello');
    });

    test('selectAll returns everything in reading order with line breaks', () {
      final r = svc.selectAll(elements);
      expect(r.indices, [0, 1, 2, 3]);
      expect(r.text, 'Hello World\nFoo Bar');
    });

    test('reading order is derived from geometry, not list order', () {
      // Provide elements shuffled relative to visual order.
      final shuffled = [
        _el('Bar', 0.30, 0.20),
        _el('Hello', 0.10, 0.10),
        _el('Foo', 0.10, 0.20),
        _el('World', 0.30, 0.10),
      ];
      final r = svc.selectAll(shuffled);
      expect(r.text, 'Hello World\nFoo Bar');
    });

    test('a slanted line stays one line instead of splitting on a fixed tolerance', () {
      final slanted = [
        _el('One', 0.10, 0.100),
        _el('Two', 0.30, 0.110),
        _el('Three', 0.50, 0.120),
      ];
      final r = svc.selectAll(slanted);
      expect(r.text, 'One Two Three');
      expect(r.text.contains('\n'), isFalse);
    });

    test('Kurdish words on one line copy in reading order, right to left', () {
      final rtl = [
        _el('کوردی', 0.10, 0.10),
        _el('سڵاو', 0.55, 0.10),
      ];
      final r = svc.selectAll(rtl);
      expect(r.text, 'سڵاو کوردی');
      expect(r.indices, [1, 0]);
      expect(r.source, TextGeometrySource.native);
    });

    test('two columns are read down the left column before the right', () {
      final columns = [
        _el('A', 0.05, 0.10, w: 0.12),
        _el('B', 0.62, 0.10, w: 0.12),
        _el('C', 0.05, 0.22, w: 0.12),
        _el('D', 0.62, 0.22, w: 0.12),
      ];
      expect(svc.selectAll(columns).text, 'A\nC\nB\nD');
    });

    test('a non-finite point does not throw', () {
      final r = svc.selectRange(
        elements,
        const Offset(double.nan, 0.1),
        const Offset(0.1, 0.1),
      );
      expect(r.isEmpty, isTrue);
    });

    test('an OCR word lowers the selection confidence', () {
      final mixed = [
        const PdfTextElement(
          text: 'scan',
          rect: Rect.fromLTWH(0.1, 0.1, 0.2, 0.03),
          fontSize: 12,
          source: TextGeometrySource.ocr,
          confidence: 0.4,
        ),
      ];
      final r = svc.selectAll(mixed);
      expect(r.source, TextGeometrySource.ocr);
      expect(r.confidence, 0.4);
    });
  });
}
