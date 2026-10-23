import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/pdf_content_text_extractor.dart';

/// A one-page 300 × 400 pt PDF with Helvetica as /F5. [form] is an optional
/// Form XObject body used as /Fm1.
Uint8List onePage(String content, {String? form, String formMatrix = '1 0 0 1 0 0'}) {
  final objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Contents 4 0 R '
        '/Resources << /Font << /F5 5 0 R >> /XObject << /Fm1 6 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    if (form != null)
      '<< /Type /XObject /Subtype /Form /BBox [0 0 300 400] /Matrix [$formMatrix] '
          '/Resources << /Font << /F5 5 0 R >> >> /Length ${form.length} >>\nstream\n$form\nendstream'
    else
      'null',
  ];
  final b = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offsets.add(b.length);
    b.write('${i + 1} 0 obj\n${objs[i]}\nendobj\n');
  }
  final xref = b.length;
  b.write('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    b.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  b.write('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  return Uint8List.fromList(latin1.encode(b.toString()));
}

double leftPt(Uint8List pdf) {
  final words = const PdfContentTextExtractor().extract(pdf)[0] ?? const [];
  expect(words, isNotEmpty);
  return words.first.rect.left * 300;
}

void main() {
  // `cm` applies the new matrix first, then the current one. The extractor
  // used the opposite order, so nested scaling moved text off the page and it
  // was dropped (PyMuPDF puts this word at x = 71.6 pt).
  test('nested cm with scaling keeps text where readers show it', () {
    const content = 'q 1 0 0 1 28.34646 351.1811 cm q 2 0 0 2 43.2699 0 cm '
        'BT /F5 12 Tf 0 2.7 Td (HELLO) Tj ET Q Q';
    expect(leftPt(onePage(content)), closeTo(71.6, 0.2));
  });

  test('a scaled Form XObject maps through its /Matrix after the CTM', () {
    final pdf = onePage(
      'q 1 0 0 1 20 300 cm /Fm1 Do Q',
      form: 'BT /F5 12 Tf 10 0 Td (FORM) Tj ET',
      formMatrix: '2 0 0 2 5 0',
    );
    // x = 20 + (2 * 10 + 5) = 45
    expect(leftPt(pdf), closeTo(45, 0.2));
  });

  group('fill colour of text', () {
    Map<String, Color?> colours(Uint8List pdf) => {
          for (final w in const PdfContentTextExtractor().extract(pdf)[0] ?? const []) w.text: w.color,
        };

    test('reads gray, RGB and CMYK and restores it with Q', () {
      final c = colours(onePage('BT /F5 12 Tf 10 300 Td (DEFAULT) Tj ET '
          'q 1 0 0 rg BT /F5 12 Tf 10 280 Td (RED) Tj ET Q '
          'BT /F5 12 Tf 10 260 Td (AFTERQ) Tj ET '
          '0.5 g BT /F5 12 Tf 10 240 Td (GRAY) Tj ET '
          '0 1 1 0 k BT /F5 12 Tf 10 220 Td (CMYKRED) Tj ET'));
      expect(c['DEFAULT'], const Color(0xFF000000));
      expect(c['RED'], const Color(0xFFFF0000));
      expect(c['AFTERQ'], const Color(0xFF000000));
      expect(c['GRAY'], const Color(0xFF808080));
      expect(c['CMYKRED'], const Color(0xFFFF0000));
    });

    test('sc in a device space is read; an unknown space stays null', () {
      final c = colours(onePage('/DeviceRGB cs 0 0 1 sc BT /F5 12 Tf 10 300 Td (BLUE) Tj ET '
          '/CS9 cs 0.7 scn BT /F5 12 Tf 10 280 Td (SPOT) Tj ET '
          '/Pattern cs /P1 scn BT /F5 12 Tf 10 260 Td (PATTERN) Tj ET'));
      expect(c['BLUE'], const Color(0xFF0000FF));
      expect(c['SPOT'], isNull);
      expect(c['PATTERN'], isNull);
    });

    test('a Form XObject starts with the fill of the page that draws it', () {
      final c = colours(onePage('0 0.5 0 rg /Fm1 Do', form: 'BT /F5 12 Tf 10 300 Td (INFORM) Tj ET'));
      expect(c['INFORM'], const Color(0xFF008000));
    });
  });
}
