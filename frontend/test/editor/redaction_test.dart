import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/redaction_service.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

PdfTextElement _el(String text, Rect rect) =>
    PdfTextElement(text: text, rect: rect, fontSize: 12);

void main() {
  const svc = RedactionService();

  group('RedactionService (Phase 17)', () {
    test('removes text elements substantially covered by a region', () {
      final elements = [
        _el('secret', const Rect.fromLTWH(0.1, 0.1, 0.2, 0.05)),
        _el('public', const Rect.fromLTWH(0.1, 0.5, 0.2, 0.05)),
      ];
      final regions = [
        const RedactionRegion(Rect.fromLTWH(0.05, 0.08, 0.3, 0.1)),
      ];
      final r = svc.apply(elements, regions);
      expect(r.removedCount, 1);
      expect(r.removedIndices, [0]);
      expect(r.remainingText.map((e) => e.text), ['public']);
    });

    test('a barely-grazing region does not wipe the whole element', () {
      final elements = [
        _el('keep me', const Rect.fromLTWH(0.1, 0.1, 0.4, 0.05)),
      ];
      // Region overlaps only a sliver at the far right (< threshold).
      final regions = [
        const RedactionRegion(Rect.fromLTWH(0.49, 0.1, 0.02, 0.05)),
      ];
      final r = svc.apply(elements, regions);
      expect(r.removedCount, 0);
      expect(r.remainingText.length, 1);
    });

    test('redacted text is truly gone (not recoverable)', () {
      final elements = [
        _el('password123', const Rect.fromLTWH(0.1, 0.1, 0.3, 0.05)),
      ];
      final regions = [
        const RedactionRegion(Rect.fromLTWH(0.05, 0.05, 0.4, 0.1), label: 'PII'),
      ];
      final r = svc.apply(elements, regions);
      expect(r.remainingText, isEmpty);
      expect(
        r.remainingText.any((e) => e.text.contains('password')),
        isFalse,
      );
    });

    test('coveredElements previews indices without mutating', () {
      final elements = [
        _el('a', const Rect.fromLTWH(0.1, 0.1, 0.1, 0.05)),
        _el('b', const Rect.fromLTWH(0.1, 0.3, 0.1, 0.05)),
        _el('c', const Rect.fromLTWH(0.1, 0.5, 0.1, 0.05)),
      ];
      final regions = [
        const RedactionRegion(Rect.fromLTWH(0.05, 0.05, 0.2, 0.1)), // covers a
        const RedactionRegion(Rect.fromLTWH(0.05, 0.45, 0.2, 0.1)), // covers c
      ];
      expect(svc.coveredElements(elements, regions), [0, 2]);
      expect(elements.length, 3); // untouched
    });

    test('mergeOverlapping collapses overlapping and chained rects', () {
      final merged = svc.mergeOverlapping(const [
        Rect.fromLTWH(0.0, 0.0, 0.2, 0.2),
        Rect.fromLTWH(0.1, 0.1, 0.2, 0.2), // overlaps #1
        Rect.fromLTWH(0.25, 0.25, 0.2, 0.2), // touches #2 -> chains into one
        Rect.fromLTWH(0.8, 0.8, 0.1, 0.1), // separate
      ]);
      expect(merged.length, 2);
      // The big merged rect should span from origin to at least 0.45.
      final big = merged.firstWhere((r) => r.left == 0.0);
      expect(big.right, closeTo(0.45, 1e-9));
      expect(big.bottom, closeTo(0.45, 1e-9));
    });

    test('no regions => everything survives, no cover rects', () {
      final elements = [_el('x', const Rect.fromLTWH(0.1, 0.1, 0.1, 0.05))];
      final r = svc.apply(elements, const []);
      expect(r.removedCount, 0);
      expect(r.coverRects, isEmpty);
      expect(r.remainingText.length, 1);
    });
  });
}
