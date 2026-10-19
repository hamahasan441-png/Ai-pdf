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
      // All chars in 0..3 are bold → toggle should un-bold them → plain mode.
      final runs = svc.toggleBold(a, 0, 3);
      // After toggle: all 6 chars have null overrides → collapse returns null.
      if (runs != null) {
        fail('Expected null but got ${runs.length} runs: '
            '${runs.map((r) => "(${r.text},bold:${r.bold},it:${r.italic})").join(", ")}');
      }
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
      expect(runs[1].color!.toARGB32(), Colors.red.toARGB32());
      expect(runs[1].text, 'CD');
    });

    test('typing keeps the style of the characters around the caret', () {
      final a = TextAnnotation(
        const Offset(0, 0),
        'Hello',
        Colors.black,
        0.05,
        false,
        runs: const [TextRun('Hel', bold: true), TextRun('lo')],
      );
      final runs = svc.retarget(a, 'HelXlo');
      expect(runs, isNotNull);
      expect(runs!.map((r) => r.text).join(), 'HelXlo');
      final bold = runs.where((r) => r.bold == true).map((r) => r.text).join();
      expect(bold.contains('Hel'), isTrue);
      expect(bold.contains('X'), isTrue);
    });

    test('a bold base can be turned off for a range', () {
      final a = TextAnnotation(const Offset(0, 0), 'ABCD', Colors.black, 0.05, true);
      final runs = svc.toggleBold(a, 0, 2);
      expect(runs, isNotNull);
      expect(runs!.first.text, 'AB');
      expect(runs.first.bold, isFalse);
    });

    test('a combining mark is not styled apart from its base letter', () {
      const text = 'س\u064Eب';
      final a = TextAnnotation(const Offset(0, 0), text, Colors.black, 0.05, false);
      // Offset 1 is the fatha. The snap must include the base seen.
      final runs = svc.applyStyle(a, start: 1, end: 2, bold: true);
      expect(runs, isNotNull);
      expect(runs!.first.text, 'س\u064E');
      expect(runs.first.bold, isTrue);
    });
  });
}
