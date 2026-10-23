import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/core/services/ocr_service.dart';
import 'package:ai_pdf/features/editor/data/pdf_content_text_extractor.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/scanner/data/scan_pdf_builder.dart';
import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_page.dart';

Future<Uint8List> png(int w, int h) async {
  final rec = ui.PictureRecorder();
  Canvas(rec).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.white);
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

ScanPage page(Uint8List bytes, {String? text, List<OcrLine>? lines}) => ScanPage(
      id: 'p',
      originalBytes: bytes,
      corners: DocumentCorners.fullFrame(const Size(100, 100)),
      extractedText: text,
      ocrLines: lines,
    );

String content(Uint8List pdf) {
  final s = PdfObjectStore.parse(pdf);
  final c = s.resolve(s.pages.first.attr('/Contents'));
  final refs = c is PdfArray ? c.items : [s.pages.first.attr('/Contents')];
  return [for (final r in refs) if (r is PdfRef) latin1.decode(s.decodeStream(s.object(r.num)!))].join('\n');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a tall image is centred inside the margins with its aspect ratio', () {
    final r = ScanPdfBuilder.imageRect(400, 1200);
    expect(r.height, closeTo(ScanPdfBuilder.format.height - 2 * ScanPdfBuilder.margin, 0.01));
    expect(r.width / r.height, closeTo(400 / 1200, 1e-6));
    expect(r.left + r.width / 2, closeTo(ScanPdfBuilder.format.width / 2, 0.01));
    final wide = ScanPdfBuilder.imageRect(1200, 400);
    expect(wide.width, closeTo(ScanPdfBuilder.format.width - 2 * ScanPdfBuilder.margin, 0.01));
    expect(wide.top + wide.height / 2, closeTo(ScanPdfBuilder.format.height / 2, 0.01));
  });

  testWidgets('OCR lines become invisible text over the matching part of the image', (tester) async {
    late Uint8List pdf;
    late Uint8List plain;
    await tester.runAsync(() async {
      final bytes = await png(400, 600);
      const lines = [OcrLine('INVOICE 4711', 0.1, 0.1, 0.5, 0.05), OcrLine('Total 99', 0.6, 0.8, 0.3, 0.04)];
      pdf = await const ScanPdfBuilder().build(
        [page(bytes, text: 'INVOICE 4711\nTotal 99', lines: lines)],
        searchable: true,
      );
      plain = await const ScanPdfBuilder().build(
        [page(bytes, text: 'INVOICE 4711', lines: lines)],
        searchable: false,
      );
      if (Platform.environment['PDOCZY_SCAN_OUT'] case final out?) {
        File('$out/scan_searchable.pdf').writeAsBytesSync(pdf);
      }
    });

    expect(content(pdf), contains('3 Tr'), reason: 'text render mode 3 is invisible');
    expect(content(plain), isNot(contains('BT')), reason: 'no text layer when not searchable');

    final words = const PdfContentTextExtractor().extract(pdf)[0] ?? const [];
    final invoice = words.firstWhere((w) => w.text.contains('INVOICE'));
    // The image fills a 400:600 box centred in the A4 margins; map the OCR
    // box into that box and compare in page-normalized units.
    final r = ScanPdfBuilder.imageRect(400, 600);
    final pageW = ScanPdfBuilder.format.width;
    final pageH = ScanPdfBuilder.format.height;
    final expectedLeft = (r.left + 0.1 * r.width) / pageW;
    final expectedTop = (r.top + 0.1 * r.height) / pageH;
    expect(invoice.rect.left, closeTo(expectedLeft, 0.02));
    expect(invoice.rect.top, closeTo(expectedTop, 0.03));
    expect(words.map((w) => w.text).join(' '), contains('99'));
  });

  testWidgets('a page with text but no positions gets one invisible block', (tester) async {
    late Uint8List pdf;
    await tester.runAsync(() async {
      pdf = await const ScanPdfBuilder().build(
        [page(await png(300, 300), text: 'Plain OCR text')],
        searchable: true,
      );
    });
    expect(content(pdf), contains('3 Tr'));
    final text = (const PdfContentTextExtractor().extract(pdf)[0] ?? const []).map((w) => w.text).join(' ');
    expect(text, contains('Plain'));
  });
}
