import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/pdf_content_text_extractor.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_text_eraser.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

final widths600 = '/FirstChar 32 /LastChar 126 /Widths [${'600 ' * 95}]';

/// A 400 × 300 pt page. /F1 is a simple font with /Widths (600 for every
/// character), /F2 Helvetica without widths, /F3 an Identity-H CID font
/// (500 per glyph), /Fm a form with text.
Uint8List page(String content, {String form = 'BT /F1 10 Tf 50 50 Td (FORM) Tj ET'}) {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Contents 4 0 R '
        '/Resources << /Font << /F1 5 0 R /F2 6 0 R /F3 7 0 R >> /XObject << /Fm 9 0 R >> >> >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /TrueType /BaseFont /Mono $widths600 >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /Font /Subtype /Type0 /BaseFont /Cid /Encoding /Identity-H /DescendantFonts [8 0 R] '
        '/ToUnicode 10 0 R >>',
    '<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Cid /DW 500 /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> >>',
    '<< /Type /XObject /Subtype /Form /BBox [0 0 400 300] /Resources << /Font << /F1 5 0 R >> >> '
        '/Length ${form.length} >>\nstream\n$form\nendstream',
    _toUnicode(),
  ];
  final b = BytesBuilder()..add(latin1.encode('%PDF-1.7\n'));
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(b.length);
    b.add(latin1.encode('${i + 1} 0 obj\n${objects[i]}\nendobj\n'));
  }
  final xref = b.length;
  final t = StringBuffer('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    t.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  t.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  b.add(latin1.encode(t.toString()));
  return b.toBytes();
}

/// CIDs 0x41.. map to A.. so the extractor can read the CID text.
String _toUnicode() {
  const cmap = '/CIDInit /ProcSet findresource begin 12 dict begin begincmap '
      '1 begincodespacerange <0000> <FFFF> endcodespacerange '
      '1 beginbfrange <0041> <005A> <0041> endbfrange endcmap end end';
  return '<< /Length ${cmap.length} >>\nstream\n$cmap\nendstream';
}

/// Erases [regions] (user space) on page 1 of [pdf], returns the result and
/// the page rebuilt with the new content.
(TextEraseResult, Uint8List) eraseIn(Uint8List pdf, List<UserRect> regions) {
  final s = PdfObjectStore.parse(pdf);
  final p = s.pages.first;
  final content = s.decodeStream(s.object((p.dict['/Contents'] as PdfRef).num)!);
  final r = PdfTextEraser(s).erase(content, p.attr('/Resources'), regions);
  final text = latin1.decode(pdf);
  final old = latin1.decode(content);
  final rebuilt = text.replaceFirst('<< /Length ${old.length} >>\nstream\n$old\nendstream',
      '<< /Length ${r.content.length} >>\nstream\n${latin1.decode(r.content)}\nendstream');
  // Offsets changed: re-number the xref by re-building from scratch.
  return (r, _reflow(rebuilt));
}

Uint8List _reflow(String pdf) {
  final objs = RegExp(r'(\d+) 0 obj\n([\s\S]*?)\nendobj\n').allMatches(pdf).map((m) => m[2]!).toList();
  final b = BytesBuilder()..add(latin1.encode('%PDF-1.7\n'));
  final offsets = <int>[];
  for (var i = 0; i < objs.length; i++) {
    offsets.add(b.length);
    b.add(latin1.encode('${i + 1} 0 obj\n${objs[i]}\nendobj\n'));
  }
  final xref = b.length;
  final t = StringBuffer('xref\n0 ${objs.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    t.write('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  t.write('trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n');
  b.add(latin1.encode(t.toString()));
  return b.toBytes();
}

/// Extracted words with their left edge in points.
Map<String, double> words(Uint8List pdf) => {
      for (final w in const PdfContentTextExtractor().extract(pdf)[0] ?? const <PdfTextElement>[])
        w.text: w.rect.left * 400,
    };

void main() {
  test('one word of a Tj is removed; the words around it do not move', () {
    // "Hello World Again" at x = 20, 6 pt per glyph at size 10.
    final pdf = page('BT /F1 10 Tf 20 100 Td (Hello World Again) Tj ET');
    final before = words(pdf);
    // "World" spans x = 20 + 6*6 = 56 .. 86.
    final (r, out) = eraseIn(pdf, [[55, 95, 87, 115]]);
    expect(r.complete, isTrue);
    expect(r.removed, 5);
    final after = words(out);
    expect(after.keys, containsAll(['Hello', 'Again']));
    expect(after.containsKey('World'), isFalse);
    expect(after['Again'], closeTo(before['Again']!, 0.01), reason: 'later text keeps its place');
    expect(after['Hello'], closeTo(before['Hello']!, 0.01));
  });

  test('a later operator in the same text object keeps its position', () {
    final pdf = page('BT /F1 10 Tf 20 100 Td (AB) Tj (CD) Tj 0 -20 Td (EF) Tj ET');
    final before = words(pdf);
    // Remove "B" (x 26..32).
    final (r, out) = eraseIn(pdf, [[27, 95, 31, 115]]);
    expect(r.removed, 1);
    final after = words(out);
    expect(after.containsKey('CD') || after.containsKey('ACD'), isTrue, reason: '$after');
    final cd = after['CD'] ?? after['ACD']!;
    expect(cd, closeTo(before['ABCD'] != null ? before['ABCD']! + 12 : before['CD']!, 0.5));
    expect(after['EF'], closeTo(before['EF']!, 0.01), reason: 'Td after it is relative to the line start');
  });

  test('TJ with kerning, Tc, Tw, Tz and the quote operators', () {
    // "ef" is its own string: the extractor spreads a chunk's width evenly
    // over its characters, so a word inside a chunk has an approximate x.
    final pdf = page('BT /F1 10 Tf 2 Tc 3 Tw 80 Tz 12 TL 20 200 Td [(ab) -120 (cd) -300 (ef)] TJ '
        "(gh) ' 1 0.5 (ij kl) \" ET");
    final before = words(pdf);
    // Erase "cd" on the first line only: glyphs advance (6 + 2) × 0.8 = 6.4 pt,
    // so "cd" runs 33.76 .. 46.56 after "ab" and the -120 kern.
    final s = PdfObjectStore.parse(pdf);
    expect(s.pages, hasLength(1));
    final cdLeft = before['abcd'] ?? before['cd'];
    expect(cdLeft, isNotNull, reason: '$before');
    final (r, out) = eraseIn(pdf, [[33, 195, 46.5, 215]]);
    expect(r.complete, isTrue, reason: 'removed ${r.removed}');
    expect(r.removed, greaterThan(0));
    final after = words(out);
    expect(after['ef'], closeTo(before['ef']!, 0.05));
    expect(after['gh'], closeTo(before['gh']!, 0.05));
    expect(after['kl'], closeTo(before['kl']!, 0.05));
  });

  test('two-byte Identity-H text is removed per glyph', () {
    // CIDs 0x41 0x42 0x43 = "ABC", 5 pt each at size 10.
    final pdf = page('BT /F3 10 Tf 20 100 Td <004100420043> Tj ET');
    final (r, out) = eraseIn(pdf, [[26, 95, 29, 115]]); // B: 25..30
    expect(r.complete, isTrue);
    expect(r.removed, 1);
    final text = (const PdfContentTextExtractor().extract(out)[0] ?? const []).map((w) => w.text).join(' ');
    expect(text.replaceAll(' ', ''), 'AC');
  });

  test('a font without widths or text in a form is reported, not half erased', () {
    final noWidths = page('BT /F2 10 Tf 20 100 Td (Hello) Tj ET');
    final (r1, _) = eraseIn(noWidths, [[0, 90, 400, 120]]);
    expect(r1.complete, isFalse);
    final inForm = page('q /Fm Do Q');
    final (r2, _) = eraseIn(inForm, [[40, 40, 120, 70]]);
    expect(r2.complete, isFalse);
    final formElsewhere = page('q /Fm Do Q BT /F1 10 Tf 20 200 Td (Hi) Tj ET', form: 'BT /F1 10 Tf 300 20 Td (X) Tj ET');
    final (r3, _) = eraseIn(formElsewhere, [[15, 195, 40, 215]]);
    expect(r3.complete, isTrue, reason: "the form's text is outside the region");
  });

  test('everything else is copied byte for byte, inline images too', () {
    const img = 'BI /W 2 /H 1 /CS /G /BPC 8 ID \x00\xff EI';
    const content = 'q 1 0 0 rg 10 10 50 50 re f Q $img BT /F1 10 Tf 20 100 Td (Keep) Tj ET';
    final pdf = page(content);
    final (r, _) = eraseIn(pdf, [[300, 0, 400, 50]]);
    expect(r.removed, 0);
    expect(latin1.decode(r.content), content, reason: 'nothing in the region: unchanged');
    final (r2, _) = eraseIn(pdf, [[19, 95, 45, 115]]);
    expect(latin1.decode(r2.content), startsWith('q 1 0 0 rg 10 10 50 50 re f Q $img BT /F1 10 Tf 20 100 Td '));
  });

  test('display rectangles map back to user space for every rotation', () {
    const crop = [10.0, 20.0, 410.0, 620.0];
    for (final rot in [0, 90, 180, 270]) {
      final user = [100.0, 200.0, 150.0, 260.0];
      final d = displayRect(user, crop, rot);
      final back = userRectOf([d.left, d.top, d.right, d.bottom], crop, rot);
      for (var i = 0; i < 4; i++) {
        expect(back[i], closeTo(user[i], 1e-9), reason: 'rotate $rot');
      }
    }
  });
}
