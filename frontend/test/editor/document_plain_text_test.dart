import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/document_plain_text.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

PdfTextElement word(String text, double left, [double top = 0, double w = 0.05, double h = 0.02]) =>
    PdfTextElement(text: text, rect: Rect.fromLTWH(left, top, w, h), fontSize: 10);

void main() {
  test('words on one visual line join in reading order', () {
    final text = plainTextFromTextLayer({
      0: [word('Hello', 0.1), word('world', 0.3), word('!', 0.6)],
    });
    expect(text, 'Hello world !');
  });

  test('lines separated by vertical distance produce newlines', () {
    final text = plainTextFromTextLayer({
      0: [
        word('First', 0.1, 0.10),
        word('line', 0.2, 0.10),
        word('Second', 0.1, 0.20),
        word('line', 0.2, 0.20),
      ],
    });
    expect(text, 'First line\nSecond line');
  });

  test('pages are separated by a blank line, in page order', () {
    final text = plainTextFromTextLayer({
      1: [word('On two', 0.1, 0.0)],
      0: [word('On one', 0.1, 0.0)],
    });
    expect(text, 'On one\n\nOn two');
  });

  test('empty pages and blank words contribute nothing', () {
    final text = plainTextFromTextLayer({
      0: const [],
      1: [word('  ', 0.1, 0.0), word('Real', 0.2, 0.0)],
      2: const [],
    });
    expect(text, 'Real');
  });

  test('slightly raised sub/superscripts stay on their line', () {
    // A superscript raised by ~40% of the base height joins the base line
    // (the band follows the taller element); the next real line at 0.15
    // starts a new row.
    final text = plainTextFromTextLayer({
      0: [
        word('x', 0.1, 0.10),
        word('2', 0.13, 0.095, 0.015, 0.012),
        word('Next', 0.1, 0.15),
      ],
    });
    expect(text, 'x 2\nNext');
  });
}
