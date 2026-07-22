import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/editor_rich_text_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

void main() {
  const svc = EditorRichTextService();

  group('EditorRichTextService (Phase 9)', () {
    test('applyStyle creates runs from a plain annotation', () {
      final a = TextAnnotation(const Offset(0, 0), 'Hello world', Colors.black, 0.05, false);
      final runs = svc.applyStyle(a, start: 0, end: 5, bold: true);
      expect(runs, isNotNull);
      expect(runs, hasLength(2));
      expect(runs![0].text, 'Hello');
      expect(runs[0].bold, isTrue);
      expect(runs[1].text, ' world');
      expect(runs[1].bold, isNull); // no override → inherit base
    });

    test('toggleBold toggles an already-bold selection off', () {
      final a = TextAnnotation(
        const Offset(0, 0),
        'ABCDEF',
        Colors.black,
        0.05,
        false,
        runs: const [TextRun('ABC', bold: true), TextRun('DEF')],
      );
      // All chars in 0..3 are bold → toggle should un-bold them.
      final runs = svc.toggleBold(a, 0, 3);
      expect(runs, isNull); // all chars now have no overrides → plain mode
    });

    test('toggleItalic applies italic to a range within existing runs', () {
      final a = TextAnnotation(
        const Offset(0, 0),
        'Hello world',
        Colors.black,
        0.05,
        false,
        runs: const [TextRun('Hello ', bold: true), TextRun('world')],
      );
      final runs = svc.toggleItalic(a, 3, 8); // "lo wo" italic
      expect(runs, isNotNull);
      // Should have splits around the italic range.
      final italicChars = runs!.where((r) => r.italic == true);
      expect(italicChars.isNotEmpty, isTrue);
    });

    test('applyStyle with colour creates a coloured run', () {
      final a = TextAnnotation(const Offset(0, 0), 'ABCDEF', Colors.black, 0.05, false);
      final runs = svc.applyStyle(a, start: 2, end: 4, color: Colors.red);
      expect(runs, isNotNull);
      // "AB" (no override) | "CD" (red) | "EF" (no override) = 3 runs.
      expect(runs!.length, 3);
      expect(runs[1].color!.value, Colors.red.value);
      expect(runs[1].text, 'CD');
    });

    test('out-of-range calls are no-ops', () {
      final a = TextAnnotation(const Offset(0, 0), 'ABC', Colors.black, 0.05, false);
      expect(svc.applyStyle(a, start: 5, end: 10, bold: true), isNull);
      expect(svc.applyStyle(a, start: 2, end: 1, bold: true), isNull);
    });
  });
}
