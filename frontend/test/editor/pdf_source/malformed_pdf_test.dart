import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';

/// Malformed PDFs must be reported as [PdfSourceException] (or recovered
/// from) — never crash with an uncaught TypeError. Regression tests for the
/// type-safe reads in PdfObjectStore (xref streams, object streams, page
/// tree walk).
///
/// The ObjStm fixture builds a real cross-reference stream (binary rows,
/// /W [1 4 1]) so the object IS reached through a type-2 entry; the parser's
/// scan reconstruction would otherwise repair the file and bypass the path
/// under test.
Uint8List pdf(String body) => utf8.encode(body);

void main() {
  test('a broken xref stream falls back to reconstruction instead of crashing', () {
    // Object 4 is a stream the trailer points at via startxref; /W is a
    // number where an array belongs. Before the type-safe read this threw an
    // uncaught TypeError out of parse().
    const base = '%PDF-1.7\n'
        '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'
        '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'
        '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 9 9] >> endobj\n';
    const startxrefOffset = base.length;
    const body = '$base'
        '4 0 obj << /W 17 /Size 5 /Length 4 >> stream\nabcd\nendstream endobj\n'
        'startxref\n$startxrefOffset\n'
        '%%EOF';
    final store = PdfObjectStore.parse(pdf(body));
    // The xref stream was unreadable, but the object scan rebuilds the file.
    expect(store.pages, hasLength(1));
  });

  test('a page reached through an object stream with a malformed /First raises PdfSourceException', () {
    final bytes = _objStmFixture('/First notanumber');
    expect(
      () => PdfObjectStore.parse(bytes),
      throwsA(isA<PdfSourceException>()),
    );
  });

  test('a well-formed object-stream fixture still resolves its page', () {
    // Sanity for the fixture builder itself: /First 4 skips the pair list
    // ("4 0 ") and the page dict is read from inside the stream.
    final bytes = _objStmFixture('/First 4');
    final store = PdfObjectStore.parse(bytes);
    expect(store.pages, hasLength(1));
  });

  test('a page tree whose /Pages is not a dictionary raises PdfSourceException', () {
    // The catalog's /Pages points at a number. The old code cast it
    // unguarded (`as PdfDict?`) inside _collectPages.
    const body = '%PDF-1.7\n'
        '1 0 obj << /Type /Catalog /Pages 5 0 R >> endobj\n'
        '5 0 obj 42 endobj\n'
        'trailer << /Size 6 /Root 1 0 R >>\n'
        '%%EOF';
    expect(
      () => PdfObjectStore.parse(pdf(body)),
      throwsA(isA<PdfSourceException>()),
    );
  });

  test('a malformed /Index in a readable xref stream never escapes as TypeError', () {
    const base = '%PDF-1.7\n'
        '1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n'
        '2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj\n'
        '3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 9 9] >> endobj\n';
    const startxrefOffset = base.length;
    const body = '$base'
        '4 0 obj << /W [1 2 1] /Index notanarray /Size 5 /Length 8 >> stream\n12345678\nendstream endobj\n'
        'startxref\n$startxrefOffset\n'
        '%%EOF';
    // Reconstruction saves the document; the important part is that nothing
    // escapes as TypeError.
    final store = PdfObjectStore.parse(pdf(body));
    expect(store.pages, hasLength(1));
  });
}

/// One-page PDF where object 4 (the page) lives inside object stream 3, and
/// the xref stream (object 5) routes it there with a type-2 entry.
///
/// [objStmDictExtra] controls the ObjStm dict so a test can corrupt /First.
Uint8List _objStmFixture(String objStmDictExtra) {
  final out = BytesBuilder();
  var pos = 0;
  void add(String s) {
    final chunk = utf8.encode(s);
    out.add(chunk);
    pos += chunk.length;
  }

  add('%PDF-1.5\n');
  final off1 = pos;
  add('1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n');
  final off2 = pos;
  add('2 0 obj << /Type /Pages /Kids [4 0 R] /Count 1 >> endobj\n');
  const stmBody = '4 0 << /Type /Page /Parent 2 0 R /MediaBox [0 0 9 9] >>';
  final off3 = pos;
  add('3 0 obj << /Type /ObjStm /N 1 $objStmDictExtra /Length ${stmBody.length} >> stream\n$stmBody\nendstream endobj\n');
  add('4 0 obj 999 endobj\n'); // decoy: the xref points into the stream instead
  final off5 = pos;

  // Cross-reference stream: /W [1 4 1], /Index [1 5].
  final rows = BytesBuilder();
  void row(int type, int value, int gen) {
    rows.addByte(type);
    final v = ByteData(4)..setUint32(0, value);
    rows.add(v.buffer.asUint8List());
    rows.addByte(gen);
  }

  row(1, off1, 0); // 1 catalog
  row(1, off2, 0); // 2 pages
  row(1, off3, 0); // 3 objstm
  row(2, 3, 0);    // 4 -> inside object stream 3, index 0
  row(1, off5, 0); // 5 the xref stream itself
  final xrefData = rows.toBytes();

  add('5 0 obj << /Type /XRef /W [1 4 1] /Index [1 5] /Size 6 /Root 1 0 R /Length ${xrefData.length} >> stream\n');
  out.add(xrefData);
  pos += xrefData.length;
  add('\nendstream endobj\n');
  add('startxref\n$off5\n%%EOF');
  return out.toBytes();
}
