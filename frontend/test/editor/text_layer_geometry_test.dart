import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/pdf_content_text_extractor.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

Map<int, List<PdfTextElement>> layer(String name) =>
    const PdfContentTextExtractor().extract(File('test/fixtures/pdf/$name.pdf').readAsBytesSync());

Rect word(Map<int, List<PdfTextElement>> l, int page, String text) => l[page]!.firstWhere((w) => w.text == text).rect;

void main() {
  test('word boxes are on the displayed page of a /Rotate 90 page', () {
    // PyMuPDF puts "REPLACEME" at x 157.3..224.4 on the unrotated 400 × 600
    // page, baseline y = 100 from the top. Shown turned clockwise, the page is
    // 600 × 400: x along the text becomes the vertical axis, and the line
    // sits near the right edge.
    final r = word(layer('edit_text'), 1, 'REPLACEME');
    expect(r.top, closeTo(157.3 / 400, 0.004));
    expect(r.bottom, closeTo(224.4 / 400, 0.004));
    expect(r.left, closeTo(1 - 100 / 600, 0.03));
    expect(r.right, greaterThan(r.left));
    expect(r.right, lessThanOrEqualTo(1));
  });

  test('word boxes are relative to the CropBox, not the MediaBox', () {
    // rich_classic page 3: MediaBox 600 × 800, CropBox x 300..600, y 0..400
    // (user space); the text starts at x = 350.
    final r = word(layer('rich_classic'), 2, 'ORIGINAL-SEARCHABLE-TEXT');
    expect(r.left, closeTo((350 - 300) / 300, 0.005));
    expect(r.top, inInclusiveRange(0, 1));
  });

  test('exact widths: words on one line do not overlap and keep their order', () {
    final words = layer('edit_text')[0]!.where((w) => (w.rect.top - word(layer('edit_text'), 0, 'Invoice').top).abs() < 0.001).toList();
    expect(words.map((w) => w.text), ['Invoice', 'number', '12345', 'due', 'today']);
    for (var i = 1; i < words.length; i++) {
      expect(words[i].rect.left, greaterThan(words[i - 1].rect.right), reason: '${words[i].text} after ${words[i - 1].text}');
    }
    // PyMuPDF: "12345" at x 179.2..219.2 on the 595 pt wide page.
    final n = word(layer('edit_text'), 0, '12345');
    expect(n.left * 595, closeTo(179.2, 0.5));
    expect(n.right * 595, closeTo(219.2, 0.5));
  });

  test('turning a word box clockwise four times returns it', () {
    const e = PdfTextElement(text: 'x', rect: Rect.fromLTRB(0.1, 0.2, 0.3, 0.25), fontSize: 10);
    expect(e.turned(1).rect, const Rect.fromLTRB(0.75, 0.1, 0.8, 0.3));
    expect(e.turned(4).rect, e.rect);
    expect(e.turned(1).turned(3).rect.left, closeTo(e.rect.left, 1e-12));
  });
}
