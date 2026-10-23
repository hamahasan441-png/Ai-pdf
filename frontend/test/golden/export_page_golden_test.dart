import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/editor_export_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Pixel goldens for the page image the export embeds.
///
/// These call the real export compositor ([EditorExportService]) with the
/// bundled fonts, so Sorani shaping, RTL order, wrapping and the black
/// redaction cover are compared as pixels, not as metadata. The source page
/// is a synthetic bitmap: the compositor cannot open a PDF under
/// `flutter test` (pdfx needs a device).
///
/// Regenerate after an intended change with
/// `flutter test --update-goldens test/golden/export_page_golden_test.dart`
/// and inspect the PNGs under test/golden/goldens/ before committing.
/// Failures write the diff images to test/golden/failures/.
///
/// Tolerance: 0.5 % of pixels. Anti-aliasing on another machine with the
/// same Flutter version changes far fewer; a missing join, a swapped word or
/// a lost cover changes several percent of this page.
const double _tolerance = 0.005;

const _page = Size(600, 800);

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      // From disk: NotoSans-Bold is a test font, not bundled with the app.
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await loader.load();
  }

  await family('Vazirmatn', ['Vazirmatn-Regular.ttf', 'Vazirmatn-Bold.ttf']);
  await family('NotoSansArabic', ['NotoSansArabic-Regular.ttf', 'NotoSansArabic-Bold.ttf']);
  await family('NotoSans', ['NotoSans-Regular.ttf', 'NotoSans-Bold.ttf']);
}

/// A stand-in source page: white paper, a coloured band and a grey table.
Future<Uint8List> _sourcePage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(Offset.zero & _page, Paint()..color = Colors.white);
  canvas.drawRect(const Rect.fromLTWH(0, 360, 600, 120), Paint()..color = const Color(0xFFDCEBFA));
  final grid = Paint()
    ..color = const Color(0xFF888888)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 3; c++) {
      canvas.drawRect(Rect.fromLTWH(40.0 + c * 170, 560.0 + r * 40, 170, 40), grid);
    }
  }
  final image = await recorder.endRecording().toImage(_page.width.toInt(), _page.height.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

TextAnnotation _t(
  double x,
  double y,
  String text, {
  String family = 'Vazirmatn',
  double size = 0.03,
  bool bold = false,
  double rotation = 0,
}) {
  return TextAnnotation(Offset(x, y), text, Colors.black, size, bold, fontFamily: family)
    ..rotation = rotation;
}

Future<ui.Image> _decode(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    goldenFileComparator = _TolerantComparator(
      Uri.parse('test/golden/export_page_golden_test.dart'),
    );
    await _loadFonts();
  });

  testWidgets('Sorani, Arabic and mixed text are painted into the export page', (tester) async {
    late ui.Image image;
    await tester.runAsync(() async {
      final layer = PageLayer()
        ..items.addAll([
          _t(0.05, 0.03, 'ڕ ڵ ێ ە ۆ ۊ', size: 0.05),
          _t(0.05, 0.12,
              'زمانی کوردی زمانێکی هیندوئەورووپاییە و لە ڕۆژهەڵاتی ناوەڕاست قسەی پێدەکرێت. خوێندنەوە و نووسین بە ئەلفوبێی عەرەبی دەکرێت.'),
          _t(0.05, 0.30, 'فایلی report_2024.pdf لە https://example.com (٢٠٢٤ / 2024)'),
          _t(0.05, 0.47, 'مرحبا بالعالم، ڕۆژباش', family: 'NotoSansArabic', bold: true, size: 0.035),
          _t(0.10, 0.62, 'Grüße aus Köln — Straße', family: 'NotoSans', rotation: 0.2),
          ShapeAnnotation(ShapeType.rect, const Offset(0.55, 0.40), const Offset(0.90, 0.44), Colors.black, 1, true)
            ..metadata[visualCoverKey] = true,
          ShapeAnnotation(ShapeType.rect, const Offset(0.10, 0.88), const Offset(0.50, 0.93), Colors.black, 1, true)
            ..metadata[serverRedactedKey] = true,
        ]);
      final bytes = await const EditorExportService().composePageImageForTest(
        index: 0,
        pageCache: {0: await _sourcePage()},
        layers: {0: layer},
      );
      expect(bytes, isNotNull);
      image = await _decode(bytes!);
    });
    expect(image.width, _page.width.toInt());
    expect(image.height, _page.height.toInt());
    await expectLater(image, matchesGoldenFile('goldens/export_page_rtl.png'));
  });

  testWidgets('a session rotation turns the page and keeps marks upright', (tester) async {
    late ui.Image image;
    await tester.runAsync(() async {
      final layer = PageLayer()
        ..items.add(_t(0.05, 0.05, 'ڕۆژی باش', size: 0.05))
        ..items.add(
          ShapeAnnotation(ShapeType.rect, const Offset(0.60, 0.80), const Offset(0.90, 0.90), Colors.black, 1, true)
            ..metadata[visualCoverKey] = true,
        );
      final bytes = await const EditorExportService().composePageImageForTest(
        index: 0,
        pageCache: {0: await _sourcePage()},
        layers: {0: layer},
        quarterTurns: 1,
      );
      image = await _decode(bytes!);
    });
    expect(image.width, _page.height.toInt(), reason: 'one turn swaps width and height');
    expect(image.height, _page.width.toInt());
    await expectLater(image, matchesGoldenFile('goldens/export_page_rotated.png'));
  });
}
