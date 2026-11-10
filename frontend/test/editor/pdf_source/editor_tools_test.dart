import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/editor_export_service.dart';
import 'package:ai_pdf/features/editor/data/format_painter.dart';
import 'package:ai_pdf/features/editor/data/page_measure.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_link.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/preserving_pdf_writer.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

void main() {
  test('a measurement is the page distance in millimetres', () {
    expect(
      measurePoints(Offset.zero, const Offset(1, 0), pageWidthPt: 72, pageHeightPt: 200),
      closeTo(72, 0.001),
    );
    expect(formatMillimetres(72), '25.4 mm');
    expect(
      measureLabel(Offset.zero, const Offset(0.3, 0.4), pageWidthPt: 100, pageHeightPt: 100),
      '17.6 mm',
    );
    expect(measurePoints(Offset.zero, const Offset(1, 0), pageWidthPt: 0, pageHeightPt: 100), 0);
  });

  test('web addresses are kept and anything else is refused', () {
    expect(normalizeLinkUri('example.com/a'), 'https://example.com/a');
    expect(normalizeLinkUri('https://example.com'), 'https://example.com');
    expect(normalizeLinkUri('mailto:a@b.c'), 'mailto:a@b.c');
    expect(normalizeLinkUri('not a url'), isNull);
    expect(normalizeLinkUri('javascript:alert(1)'), isNull);
  });

  test('a link is an annotation, not a mark that covers the page', () {
    final link = ShapeAnnotation(ShapeType.link, const Offset(0.1, 0.2), const Offset(0.5, 0.4), Colors.blue, 1);
    link.metadata[linkUriKey] = 'example.com/docs';
    final measure = ShapeAnnotation(ShapeType.measure, Offset.zero, const Offset(0.2, 0), Colors.black, 2);
    final layer = PageLayer()
      ..items.add(link)
      ..items.add(measure);
    expect(markNeedsOverlay(link), isFalse);
    expect(markNeedsOverlay(measure), isTrue);
    final spec = linksOf(layer).single;
    expect(spec.uri, 'https://example.com/docs');
    expect(spec.rect, [0.1, 0.2, 0.5, 0.4]);

    link.metadata
      ..remove(linkUriKey)
      ..[linkPageKey] = 3;
    expect(linksOf(layer).single.page, 3);
  });

  test('the format painter copies text and shape look and skips a locked object', () {
    final from = TextAnnotation(const Offset(0.1, 0.1), 'Hello', Colors.red, 18, true, italic: true, underline: true);
    final onto = TextAnnotation(const Offset(0.2, 0.2), 'There', Colors.blue, 11, false);
    expect(applyStyle(onto, copyStyle(from)), isTrue);
    expect(onto.color.toARGB32(), Colors.red.toARGB32());
    expect(onto.size, 18);
    expect(onto.bold, isTrue);
    expect(onto.italic, isTrue);
    expect(onto.underline, isTrue);

    final box = ShapeAnnotation(ShapeType.rect, Offset.zero, const Offset(0.2, 0.2), Colors.black, 1);
    final target = ShapeAnnotation(ShapeType.rect, const Offset(0.3, 0.3), const Offset(0.5, 0.5), Colors.green, 4, true);
    expect(applyStyle(target, copyStyle(box)), isTrue);
    expect(target.color.toARGB32(), Colors.black.toARGB32());
    expect(target.width, 1);
    expect(target.filled, isFalse);

    target.locked = true;
    target.color = Colors.green;
    expect(applyStyle(target, copyStyle(box)), isFalse);
    expect(target.color.toARGB32(), Colors.green.toARGB32());
  });

  test('a link is written into the PDF and the page text stays', () {
    final pdf = _twoPages();
    final store = PdfObjectStore.parse(pdf);
    final uriOut = PreservingPdfWriter(store, null).write([
      SourcePageSpec(0, links: [
        const PdfLinkSpec(rect: [0.1, 0.1, 0.4, 0.25], uri: 'https://example.com/a'),
      ]),
      const SourcePageSpec(1),
    ]);
    final uriStore = PdfObjectStore.parse(uriOut);
    final uriLink = _link(uriStore);
    final uriAction = uriStore.resolve(uriLink['/A']) as PdfDict;
    expect(uriAction['/S'], const PdfName('/URI'));
    expect((uriAction['/URI'] as PdfString).text, 'https://example.com/a');
    expect(latin1.decode(uriOut, allowInvalid: true), contains('PAGE-ONE'));
    expect(latin1.decode(uriOut, allowInvalid: true), contains('PAGE-TWO'));

    final pageOut = PreservingPdfWriter(PdfObjectStore.parse(pdf), null).write([
      SourcePageSpec(0, links: [
        const PdfLinkSpec(rect: [0.2, 0.2, 0.6, 0.4], page: 1),
      ]),
      const SourcePageSpec(1),
    ]);
    final pageStore = PdfObjectStore.parse(pageOut);
    final action = pageStore.resolve(_link(pageStore)['/A']) as PdfDict;
    expect(action['/S'], const PdfName('/GoTo'));
    final dest = action['/D'] as PdfArray;
    expect((dest.items.first as PdfRef).num, pageStore.pages[1].ref.num);
    expect(dest.items[1], const PdfName('/Fit'));
  });
}

PdfDict _link(PdfObjectStore store) {
  for (var n = 1; n <= store.maxObjectNumber; n++) {
    final dict = store.object(n)?.value;
    if (dict is PdfDict && dict['/Subtype'] == const PdfName('/Link')) return dict;
  }
  fail('no link annotation');
}

Uint8List _twoPages() {
  const one = 'BT /F1 12 Tf 72 100 Td (PAGE-ONE) Tj ET';
  const two = 'BT /F1 12 Tf 72 100 Td (PAGE-TWO) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Contents 5 0 R '
        '/Resources << /Font << /F1 7 0 R >> >> >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Contents 6 0 R '
        '/Resources << /Font << /F1 7 0 R >> >> >>',
    '<< /Length ${one.length} >>\nstream\n$one\nendstream',
    '<< /Length ${two.length} >>\nstream\n$two\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final b = BytesBuilder()..add(latin1.encode('%PDF-1.4\n'));
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
