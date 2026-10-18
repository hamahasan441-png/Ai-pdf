import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show PdfColors, PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;

import 'package:ai_pdf/features/editor/data/editor_export_service.dart';
import 'package:ai_pdf/features/editor/data/pdf_content_text_extractor.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/preserving_pdf_writer.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Source-preserving export against synthetic PDFs made by
/// test/fixtures/pdf/make_fixtures.py.
///
/// With PDOCZY_EXPORT_OUT set, the service tests also write their output and
/// an expectations file there; tool/verify_preserving_export.py then checks
/// the same bytes with PyMuPDF and qpdf (CI runs both).

const keep = 'ORIGINAL-SEARCHABLE-TEXT';
const secret = 'SECRET-REDACT-74192';

Uint8List fixture(String name) => File('test/fixtures/pdf/$name.pdf').readAsBytesSync();

PdfObjectStore store(String name) => PdfObjectStore.parse(fixture(name));

/// Every decoded stream in [s], concatenated.
Uint8List allStreams(PdfObjectStore s) {
  final out = BytesBuilder();
  for (var n = 1; n <= s.maxObjectNumber; n++) {
    final o = s.object(n);
    if (o?.stream == null) continue;
    try {
      out.add(s.decodeStream(o!));
    } on PdfSourceException {
      out.add(o!.stream!);
    }
  }
  return out.toBytes();
}

bool containsBytes(Uint8List hay, Uint8List needle) {
  if (needle.isEmpty || needle.length > hay.length) return false;
  outer:
  for (var i = 0; i <= hay.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

/// Decoded content of source page [index].
Uint8List pageContent(PdfObjectStore s, int index) {
  final c = s.resolve(s.pages[index].attr('/Contents'));
  final refs = c is PdfArray ? c.items : [s.pages[index].attr('/Contents')];
  final out = BytesBuilder();
  for (final r in refs) {
    if (r is PdfRef) out.add(s.decodeStream(s.object(r.num)!));
  }
  return out.toBytes();
}

String pageText(Uint8List pdf, int page) =>
    (const PdfContentTextExtractor().extract(pdf)[page] ?? const []).map((e) => e.text).join(' ');

int annotCount(PdfObjectStore s, int page) {
  final a = s.resolve(s.pages[page].dict['/Annots']);
  return a is PdfArray ? a.items.length : 0;
}

Future<PdfObjectStore> overlayDoc(PdfObjectStore src) async {
  final doc = pw.Document();
  for (final p in src.pages) {
    final c = p.cropBox;
    final odd = p.rotate % 180 != 0;
    final w = odd ? c[3] - c[1] : c[2] - c[0];
    final h = odd ? c[2] - c[0] : c[3] - c[1];
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat(w, h, marginAll: 0),
      build: (_) => pw.Stack(children: [
        pw.Positioned(left: w * 0.1, top: h * 0.1, child: pw.Container(width: w * 0.2, height: h * 0.1, color: PdfColors.red)),
      ]),
    ));
  }
  return PdfObjectStore.parse(await doc.save());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PdfObjectStore', () {
    test('reads classic xref, xref streams with object streams, /Prev chains and inheritance', () {
      for (final name in ['rich_classic', 'rich_objstm']) {
        final s = store(name);
        expect(s.pages, hasLength(3), reason: name);
        expect(s.pages[0].cropBox, [0, 0, 595, 842]);
        expect(s.pages[1].rotate, 90);
        expect(s.pages[2].cropBox, [300, 0, 600, 400]);
        expect(s.catalog['/Outlines'], isNotNull);
        expect(s.catalog['/AcroForm'], isNotNull);
      }
      final inc = store('incremental');
      expect(inc.pages, hasLength(1));
      expect(utf8.decode(pageContent(inc, 0), allowMalformed: true), isNotEmpty);
      final inh = store('inherited');
      expect(inh.pages.single.rotate, 180, reason: '/Rotate on the Pages node');
      expect(inh.pages.single.mediaBox, [0, 0, 500, 400]);
      expect(inh.pages.single.attr('/Resources'), isA<PdfDict>());
    });

    test('refuses encrypted, truncated and non-PDF input', () {
      expect(
        () => store('encrypted'),
        throwsA(isA<PdfSourceException>().having((e) => e.encrypted, 'encrypted', isTrue)),
      );
      expect(() => store('truncated'), throwsA(isA<PdfSourceException>()));
      expect(() => PdfObjectStore.parse(Uint8List.fromList(utf8.encode('<html>not a pdf</html>'))),
          throwsA(isA<PdfSourceException>()));
    });

    test('values survive a write/read round trip', () {
      final lex = PdfLexer(
        Uint8List.fromList(latin1.encode('<< /A [1 2.5 -3 (x\\)y) <414243> /N#20x 7 0 R true null] /B << /C 1 >> >>')),
        0,
      );
      final v = lex.readValue();
      final out = BytesBuilder();
      writePdfValue(out, v, (r) => r);
      final again = PdfLexer(out.toBytes(), 0).readValue();
      final out2 = BytesBuilder();
      writePdfValue(out2, again, (r) => r);
      expect(out2.toBytes(), out.toBytes());
      expect(((v as PdfDict)['/A'] as PdfArray).items[6], const PdfRef(7, 0));
    });
  });

  group('damaged input', () {
    test('truncations and corrupted bytes never crash: parse succeeds or refuses', () {
      for (final name in ['rich_classic', 'rich_objstm', 'incremental']) {
        final good = fixture(name);
        var refused = 0;
        var parsed = 0;
        void attempt(Uint8List bytes) {
          try {
            final s = PdfObjectStore.parse(bytes);
            // Whatever parsed must also be writable or refused cleanly.
            try {
              PreservingPdfWriter(s, null).write([for (var i = 0; i < s.pages.length; i++) SourcePageSpec(i)]);
            } on PdfSourceException {
              refused++;
            }
            parsed++;
          } on PdfSourceException {
            refused++;
          }
        }

        for (var cut = 16; cut < good.length; cut += 37) {
          attempt(Uint8List.sublistView(good, 0, cut));
        }
        var seed = 7;
        for (var round = 0; round < 60; round++) {
          final bad = Uint8List.fromList(good);
          for (var k = 0; k < 6; k++) {
            seed = (seed * 1103515245 + 12345) & 0x7fffffff;
            bad[seed % bad.length] = seed & 0xFF;
          }
          attempt(bad);
        }
        expect(parsed + refused, greaterThan(0), reason: name);
      }
    });
  });

  group('scale', () {
    test('a 600-page document parses and rewrites in bounded time', () async {
      final doc = pw.Document();
      for (var i = 0; i < 600; i++) {
        doc.addPage(pw.Page(build: (_) => pw.Text('$keep $i')));
      }
      final bytes = await doc.save();
      final sw = Stopwatch()..start();
      final s = PdfObjectStore.parse(bytes);
      final parseMs = sw.elapsedMilliseconds;
      final out = PreservingPdfWriter(s, null).write([
        for (var i = 599; i >= 0; i--) SourcePageSpec(i),
      ]);
      final totalMs = sw.elapsedMilliseconds;
      final back = PdfObjectStore.parse(out);
      expect(back.pages, hasLength(600));
      // ignore: avoid_print
      print('600 pages, ${bytes.length} bytes: parse ${parseMs}ms, parse+reverse+write ${totalMs}ms');
      expect(totalMs, lessThan(20000));
    });
  });

  group('overlayMatrix', () {
    test('maps the displayed page corners onto the CropBox for each rotation', () {
      const crop = [300.0, 0.0, 600.0, 400.0];
      (double, double) apply(List<double> m, double x, double y) =>
          (m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]);
      for (final r in [0, 90, 180, 270]) {
        final odd = r % 180 != 0;
        final w = odd ? 400.0 : 300.0;
        final h = odd ? 300.0 : 400.0;
        final m = overlayMatrix(crop: crop, rotate: r, formWidth: w, formHeight: h);
        final corners = {apply(m, 0, 0), apply(m, w, 0), apply(m, 0, h), apply(m, w, h)};
        expect(corners, {(300.0, 0.0), (600.0, 0.0), (300.0, 400.0), (600.0, 400.0)}, reason: 'rotate $r');
      }
      // The top-left of the displayed page for /Rotate 90 is the unrotated
      // bottom-left corner of the CropBox.
      final m90 = overlayMatrix(crop: crop, rotate: 90, formWidth: 400, formHeight: 300);
      expect(apply(m90, 0, 300), (300.0, 0.0));
    });
  });

  group('PreservingPdfWriter', () {
    for (final name in ['rich_classic', 'rich_objstm']) {
      test('$name: identity keeps text, links, notes, form fields, outline and metadata', () {
        final src = store(name);
        final out = PreservingPdfWriter(src, null).write([for (var i = 0; i < 3; i++) SourcePageSpec(i)]);
        final back = PdfObjectStore.parse(out);
        expect(back.pages, hasLength(3));
        for (var i = 0; i < 3; i++) {
          expect(back.pages[i].cropBox, src.pages[i].cropBox);
          expect(back.pages[i].rotate, src.pages[i].rotate);
          expect(pageContent(back, i), pageContent(src, i), reason: 'page $i content is untouched');
        }
        expect(annotCount(back, 0), annotCount(src, 0));
        expect(back.resolve((back.resolve(back.catalog['/AcroForm']) as PdfDict)['/Fields']), isA<PdfArray>());
        expect(back.catalog['/Outlines'], isNotNull);
        final info = back.resolve(back.trailer['/Info']) as PdfDict;
        expect(latin1.decode((info['/Title'] as PdfString).raw), contains('Pdoczy Fixture'));
        expect(pageText(out, 0), contains(keep));
      });

      test('$name: a deleted page and its content are gone; order and duplicates follow the spec', () {
        final src = store(name);
        final writer = PreservingPdfWriter(src, null);
        final out = writer.write(const [SourcePageSpec(2), SourcePageSpec(0), SourcePageSpec(0)]);
        final back = PdfObjectStore.parse(out);
        expect(back.pages, hasLength(3));
        expect(back.pages[0].cropBox, [300, 0, 600, 400]);
        expect(containsBytes(allStreams(back), pageContent(src, 1)), isFalse,
            reason: 'page two content must not be in the file');
        // The duplicate gets its own copies of the link and note, not the widget.
        final dupAnnots = back.resolve(back.pages[2].dict['/Annots']) as PdfArray;
        final kinds = [for (final a in dupAnnots.items) ((back.resolve(a) as PdfDict)['/Subtype'] as PdfName).name];
        expect(kinds, containsAll(['/Link', '/Text']));
        expect(kinds, isNot(contains('/Widget')));
        expect(writer.report!.keptSourcePages, 2);
      });
    }

    test('overlays land on every page and keep the original content', () async {
      final src = store('rich_classic');
      final ov = await overlayDoc(src);
      final out = PreservingPdfWriter(src, ov).write([
        for (var i = 0; i < 3; i++) SourcePageSpec(i, overlayPage: i, quarterTurns: i == 2 ? 1 : 0),
      ]);
      final back = PdfObjectStore.parse(out);
      expect(back.pages[2].rotate, 90);
      for (var i = 0; i < 3; i++) {
        final content = utf8.decode(pageContent(back, i), allowMalformed: true);
        expect(content, startsWith('q\n'));
        expect(content, contains('/PdoczyOverlay0 Do'));
        expect(containsBytes(pageContent(back, i), pageContent(src, i)), isTrue);
      }
    });

    test('a flattened page replaces the source page; bookmarks follow it', () async {
      final src = store('rich_objstm');
      final ov = await overlayDoc(src);
      final out = PreservingPdfWriter(src, ov).write(const [
        SourcePageSpec(0),
        GeneratedPageSpec(1, replacesSource: 1),
        SourcePageSpec(2),
      ]);
      final back = PdfObjectStore.parse(out);
      expect(containsBytes(allStreams(back), pageContent(src, 1)), isFalse);
      // The "Second" bookmark now targets output page 2.
      final outlines = back.resolve(back.catalog['/Outlines']) as PdfDict;
      final secondItem = back.resolve((back.resolve(outlines['/First']) as PdfDict)['/Next']) as PdfDict;
      final dest = back.resolve(secondItem['/Dest']) ??
          back.resolve((back.resolve(secondItem['/A']) as PdfDict?)?['/D']);
      expect((dest as PdfArray).items.first, back.pages[1].ref);
    });

    test('a field whose widget is on a removed page is dropped with its value', () {
      final src = store('rich_classic');
      final writer = PreservingPdfWriter(src, null);
      final out = writer.write(const [SourcePageSpec(1), SourcePageSpec(2)]);
      final back = PdfObjectStore.parse(out);
      final acro = back.resolve(back.catalog['/AcroForm']) as PdfDict;
      expect((back.resolve(acro['/Fields']) as PdfArray).items, isEmpty);
      expect(containsBytes(out, Uint8List.fromList(latin1.encode('Form Value Kept'))), isFalse);
      expect(writer.report!.droppedFormFields, greaterThan(0));
    });
  });

  group('EditorExportService.renderPreservingPdfFile', () {
    late Directory tmp;
    final expectations = <Map<String, Object?>>[];
    final outDir = Platform.environment['PDOCZY_EXPORT_OUT'];

    setUp(() => tmp = Directory.systemTemp.createTempSync('preserve'));
    tearDown(() => tmp.deleteSync(recursive: true));
    tearDownAll(() {
      if (outDir != null) {
        File('$outDir/expectations.json').writeAsStringSync(jsonEncode(expectations));
      }
    });

    Future<Uint8List> whitePng(int w, int h) async {
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.white);
      final img = await rec.endRecording().toImage(w, h);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }

    void keepFor(String name, String path, Map<String, Object?> expect) {
      if (outDir == null) return;
      File(path).copySync('$outDir/$name.pdf');
      expectations.add({'file': '$name.pdf', ...expect});
    }

    testWidgets('marks, a whiteout page and a turned page in one export', (tester) async {
      await tester.runAsync(() async {
        final source = '${tmp.path}/rich.pdf';
        File(source).writeAsBytesSync(fixture('rich_classic'));
        final layers = <int, PageLayer>{
          0: PageLayer()
            ..items.addAll([
              ShapeAnnotation(ShapeType.oval, const Offset(0.1, 0.1), const Offset(0.3, 0.2), Colors.red, 4, true),
              TextAnnotation(const Offset(0.1, 0.3), 'OVERLAY-TEXT', Colors.black, 0.02, false),
            ]),
          1: PageLayer()
            ..items.add(ShapeAnnotation(ShapeType.whiteout, const Offset(0, 0), const Offset(1, 0.3), Colors.white, 1)),
          2: PageLayer()
            ..items.add(ShapeAnnotation(ShapeType.oval, const Offset(0.1, 0.1), const Offset(0.3, 0.2), Colors.red, 4, true)),
        };
        final result = await const EditorExportService().renderPreservingPdfFile(
          sourcePath: source,
          doc: null,
          pageCache: {1: await whitePng(792, 612)},
          layers: layers,
          pageCount: 3,
          sourcePages: const [0, 1, 2],
          quarterTurns: const {2: 1},
          outputDirectory: () async => tmp,
        );
        expect(result.flattenedPages, [1]);
        final bytes = File(result.path).readAsBytesSync();
        final back = PdfObjectStore.parse(bytes);
        final src = store('rich_classic');
        expect(back.pages, hasLength(3));
        expect(pageText(bytes, 0), allOf(contains(keep), contains('OVERLAY-TEXT')));
        expect(pageText(bytes, 2), contains(keep));
        expect(back.pages[2].rotate, 90);
        expect(annotCount(back, 0), annotCount(src, 0), reason: 'link, note and widget stay');
        expect(containsBytes(allStreams(back), pageContent(src, 1)), isFalse,
            reason: 'the whiteout page is an image now; its text is gone');
        expect(File('${result.path}.partial').existsSync(), isFalse);
        keepFor('service_marks', result.path, {
          'pages': [
            {'text_contains': [keep, 'OVERLAY-TEXT'], 'red_at': [0.2, 0.15], 'links': 1, 'widgets': 1},
            {'text_absent': [secret, keep]},
            {'text_contains': [keep], 'rotation': 90, 'red_at': [0.2, 0.15], 'links': 1},
          ],
          'toc_entries': 3,
          'title': 'Pdoczy Fixture',
        });
      });
    });

    testWidgets('deleting a page removes it from the file', (tester) async {
      await tester.runAsync(() async {
        final source = '${tmp.path}/rich.pdf';
        File(source).writeAsBytesSync(fixture('rich_objstm'));
        final result = await const EditorExportService().renderPreservingPdfFile(
          sourcePath: source,
          doc: null,
          pageCache: const {},
          layers: const {},
          pageCount: 2,
          sourcePages: const [0, 2],
          outputDirectory: () async => tmp,
        );
        final back = PdfObjectStore.parse(File(result.path).readAsBytesSync());
        expect(back.pages, hasLength(2));
        expect(containsBytes(allStreams(back), pageContent(store('rich_objstm'), 1)), isFalse);
        keepFor('service_delete', result.path, {
          'pages': [
            {'text_contains': [keep], 'widgets': 1},
            {'text_contains': [keep], 'text_absent': [secret]},
          ],
          'text_absent_everywhere': [secret],
        });
      });
    });

    testWidgets('images, an undecodable filter and mixed page sizes pass through unread', (tester) async {
      await tester.runAsync(() async {
        final source = '${tmp.path}/images.pdf';
        File(source).writeAsBytesSync(fixture('images'));
        final src = store('images');
        final result = await const EditorExportService().renderPreservingPdfFile(
          sourcePath: source,
          doc: null,
          pageCache: const {},
          layers: {
            0: PageLayer()..items.add(TextAnnotation(const Offset(0.5, 0.05), 'OVERLAY-TEXT', Colors.black, 0.04, false)),
          },
          pageCount: 2,
          sourcePages: const [0, 1],
          outputDirectory: () async => tmp,
        );
        expect(result.flattenedPages, isEmpty, reason: 'nothing may fall back to an image page');
        final bytes = File(result.path).readAsBytesSync();
        final back = PdfObjectStore.parse(bytes);
        expect(back.pages.map((p) => p.mediaBox), [
          [0, 0, 400, 300],
          [0, 0, 200, 500],
        ]);
        expect(containsBytes(pageContent(back, 0), pageContent(src, 0)), isTrue, reason: 'vector path and text kept');
        expect(pageContent(back, 1), pageContent(src, 1));
        expect(pageText(bytes, 0), allOf(contains(keep), contains('OVERLAY-TEXT')));

        // Each image keeps its encoded bytes and its filter, including the
        // JBIG2 stream the app cannot decode and the SMask and globals it
        // points to.
        PdfDict xobjects(PdfObjectStore s) =>
            s.resolve((s.resolve(s.pages[0].attr('/Resources')) as PdfDict)['/XObject']) as PdfDict;
        final xobjs = xobjects(back);
        final srcXobjs = xobjects(src);
        for (final name in ['/ImJ', '/ImF', '/ImB']) {
          final a = back.object((xobjs[name] as PdfRef).num)!;
          final b = src.object((srcXobjs[name] as PdfRef).num)!;
          expect(a.stream, b.stream, reason: '$name raw bytes');
          expect((a.value as PdfDict)['/Filter'], isA<PdfName>());
          expect(((a.value as PdfDict)['/Filter'] as PdfName).name, ((b.value as PdfDict)['/Filter'] as PdfName).name);
        }
        final jbig = back.object((xobjs['/ImB'] as PdfRef).num)!.value as PdfDict;
        final globals = (back.resolve(jbig['/DecodeParms']) as PdfDict)['/JBIG2Globals'] as PdfRef;
        expect(latin1.decode(back.object(globals.num)!.stream!), 'PDOCZY-JBIG2-GLOBALS');
        final masked = back.object((xobjs['/ImF'] as PdfRef).num)!.value as PdfDict;
        expect(back.object((masked['/SMask'] as PdfRef).num)!.stream, isNotNull);
        int imageCount(PdfObjectStore s) => [
              for (var n = 1; n <= s.maxObjectNumber; n++)
                if (s.object(n)?.value case PdfDict d when (d['/Subtype'] as PdfName?)?.name == '/Image') n,
            ].length;
        expect(imageCount(back), imageCount(src),
            reason: 'a text-only overlay is vector; no transparent page bitmap is added');
        keepFor('service_images', result.path, {
          'pages': [
            {'text_contains': [keep, 'OVERLAY-TEXT'], 'images': 3, 'size': [400, 300]},
            {'images': 0, 'size': [200, 500]},
          ],
        });
      });
    });

    testWidgets('an encrypted source is reported, not silently flattened', (tester) async {
      await tester.runAsync(() async {
        final source = '${tmp.path}/enc.pdf';
        File(source).writeAsBytesSync(fixture('encrypted'));
        await expectLater(
          const EditorExportService().renderPreservingPdfFile(
            sourcePath: source,
            doc: null,
            pageCache: const {},
            layers: const {},
            pageCount: 1,
            sourcePages: const [0],
            outputDirectory: () async => tmp,
          ),
          throwsA(isA<PreservingExportUnavailable>()),
        );
        expect(tmp.listSync().where((f) => f.path.contains('edited_')), isEmpty);
      });
    });

    test('pagesThatHideContent', () {
      final cover = ShapeAnnotation(ShapeType.rect, Offset.zero, const Offset(0.1, 0.1), Colors.black, 1, true)
        ..metadata[visualCoverKey] = true;
      final server = ShapeAnnotation(ShapeType.rect, Offset.zero, const Offset(0.1, 0.1), Colors.black, 1, true)
        ..metadata[serverRedactedKey] = true;
      final hidden = ShapeAnnotation(ShapeType.whiteout, Offset.zero, const Offset(0.1, 0.1), Colors.white, 1)
        ..visible = false;
      final layers = {
        0: PageLayer()..items.add(cover),
        1: PageLayer()..items.add(server),
        2: PageLayer()..items.add(hidden),
        3: PageLayer()
          ..items.add(ShapeAnnotation(ShapeType.whiteout, Offset.zero, const Offset(0.1, 0.1), Colors.white, 1)),
      };
      expect(pagesThatHideContent(layers, [0, 1, 2, 3, 4]), [0, 3]);
    });
  });
}
