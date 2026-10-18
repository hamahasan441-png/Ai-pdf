import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_outline_reader.dart';

/// A PDF made of [objects] (object 1 is the catalog, 2 the page tree with
/// three pages 3, 4 and 5).
Uint8List pdfOf(List<String> extra, {String catalogExtra = ''}) {
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R $catalogExtra >>',
    '<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 /MediaBox [0 0 200 200] >>',
    '<< /Type /Page /Parent 2 0 R >>',
    '<< /Type /Page /Parent 2 0 R >>',
    '<< /Type /Page /Parent 2 0 R >>',
    ...extra,
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

List<(String, int, int)> read(Uint8List pdf) => [
      for (final h in const PdfOutlineReader().read(PdfObjectStore.parse(pdf))) (h.title, h.page, h.level),
    ];

void main() {
  test('reads the bookmarks of the export fixtures', () {
    for (final name in ['rich_classic', 'rich_objstm']) {
      final bytes = File('test/fixtures/pdf/$name.pdf').readAsBytesSync();
      expect(read(bytes), [('First', 0, 1), ('Second', 1, 1), ('Third', 2, 1)], reason: name);
    }
  });

  test('nested items, UTF-16 titles, GoTo actions and named destinations', () {
    // Outline: Intro (p1) > [Détails (GoTo p3)], Chapter (named "ch2" → p2),
    // Legacy (old-style /Dests name → p3).
    final pdf = pdfOf(
      [
        '<< /Type /Outlines /First 7 0 R /Last 9 0 R >>', // 6
        '<< /Title (Intro) /Parent 6 0 R /Next 8 0 R /First 10 0 R /Dest [3 0 R /Fit] >>', // 7
        '<< /Title <FEFF0646062706480646> /Parent 6 0 R /Prev 7 0 R /Next 9 0 R /Dest (ch2) >>', // 8
        '<< /Title (Legacy) /Parent 6 0 R /Prev 8 0 R /Dest /old >>', // 9
        '<< /Title <FEFF004400E900740061 0069006C0073> /Parent 7 0 R /A << /S /GoTo /D [5 0 R /XYZ 0 0 0] >> >>', // 10
        '<< /Dests 12 0 R >>', // 11
        '<< /Kids [13 0 R] >>', // 12
        '<< /Names [(ch2) << /D [4 0 R /Fit] >>] /Limits [(ch2) (ch2)] >>', // 13
        '<< /old [5 0 R /Fit] >>', // 14
      ],
      catalogExtra: '/Outlines 6 0 R /Names 11 0 R /Dests 14 0 R',
    );
    expect(read(pdf), [
      ('Intro', 0, 1),
      ('Détails', 2, 2),
      ('ناون', 1, 1),
      ('Legacy', 2, 1),
    ]);
  });

  test('a cycle, a remote target and an untitled item are skipped safely', () {
    final pdf = pdfOf(
      [
        '<< /Type /Outlines /First 7 0 R >>', // 6
        '<< /Title (Here) /Next 8 0 R /Dest [4 0 R /Fit] >>', // 7
        '<< /Title (Other file) /Next 9 0 R /A << /S /GoToR /F (x.pdf) /D [0 /Fit] >> >>', // 8
        '<< /Next 7 0 R /Dest [3 0 R /Fit] >>', // 9: no title, loops back to 7
      ],
      catalogExtra: '/Outlines 6 0 R',
    );
    expect(read(pdf), [('Here', 1, 1)]);
  });

  test('literal and hex strings decode to their value', () {
    PdfString lit(String s) => PdfString(Uint8List.fromList(latin1.encode(s)));
    expect(latin1.decode(lit(r'(a\(b\)\\c\n\101\7z)').bytes), 'a(b)\\c\nA\x07z');
    expect(latin1.decode(lit('(line\\\r\ncont)').bytes), 'linecont');
    expect(latin1.decode(lit('<48 65 6c6C 6F>').bytes), 'Hello');
    expect(lit('<4>').bytes, [0x40]);
  });

  test('a file without an outline gives none', () {
    expect(read(pdfOf(const [])), isEmpty);
  });
}
