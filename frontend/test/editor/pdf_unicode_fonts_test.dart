import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart' show Colors, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat, TtfParser;
// The shaper is not exported. The test reads it to keep the copied letter
// table in PdfUnicodeFonts honest across package upgrades.
// ignore: implementation_imports
import 'package:pdf/src/pdf/font/arabic.dart' as pdf_arabic;
import 'package:pdf/widgets.dart' as pw;

import 'package:ai_pdf/features/editor/data/editor_export_service.dart';
import 'package:ai_pdf/features/editor/data/font_file_validator.dart';
import 'package:ai_pdf/features/editor/data/pdf_content_text_extractor.dart';
import 'package:ai_pdf/features/editor/data/pdf_unicode_fonts.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

const sorani = 'ڕ ڵ ێ ە ۆ ۊ';
const soraniParagraph = 'زمانی کوردی زمانێکی هیندوئەورووپاییە و لە ڕۆژهەڵاتی ناوەڕاست قسەی پێدەکرێت.';
const arabic = 'مرحبا بالعالم';
const arabicIndicDigits = '٠١٢٣٤٥٦٧٨٩';

Uint8List _font(String name) => File('assets/fonts/$name').readAsBytesSync();

Set<int> _cmap(String name) =>
    TtfParser(ByteData.sublistView(_font(name))).charToGlyphIndexMap.keys.toSet();

TextAnnotation _text(String text, {bool bold = false, String? family}) =>
    TextAnnotation(const Offset(0.1, 0.1), text, Colors.black, 0.03, bold, fontFamily: family);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('bundled fonts', () {
    const files = [
      'NotoSans-Regular.ttf',
      'NotoSans-Bold.ttf',
      'NotoSansArabic-Regular.ttf',
      'NotoSansArabic-Bold.ttf',
      'Vazirmatn-Regular.ttf',
      'Vazirmatn-Bold.ttf',
      'NotoSansHebrew-Regular.ttf',
      'NotoSansHebrew-Bold.ttf',
    ];

    for (final name in files) {
      test('$name is a real TrueType file', () {
        final bytes = _font(name);
        expect(validateTrueType(bytes).ok, isTrue, reason: validateTrueType(bytes).reason);
        expect(_cmap(name), isNotEmpty);
      });
    }

    test('every bundled font has its OFL licence next to it', () {
      for (final family in ['NotoSans', 'NotoSansArabic', 'NotoSansHebrew', 'Vazirmatn']) {
        final licence = File('assets/fonts/licenses/OFL-$family.txt').readAsStringSync();
        expect(licence, contains('SIL Open Font License, Version 1.1'));
      }
    });

    for (final name in [
      'NotoSansArabic-Regular.ttf',
      'NotoSansArabic-Bold.ttf',
      'Vazirmatn-Regular.ttf',
      'Vazirmatn-Bold.ttf',
    ]) {
      test('$name covers Sorani, Arabic and Arabic-Indic digits', () {
        final cmap = _cmap(name);
        final needed = '$sorani$soraniParagraph$arabic$arabicIndicDigits،؟'
            .runes
            .where((cp) => cp != 0x20)
            .toSet();
        expect(needed.where((cp) => !cmap.contains(cp)), isEmpty);
      });
    }

    test('Noto Sans covers German and Kurmanji Latin letters', () {
      final cmap = _cmap('NotoSans-Regular.ttf');
      for (final cp in 'Grüße aus Köln ÄÖÜß Kurmancî: şêwe çûn'.runes) {
        expect(cmap.contains(cp), isTrue, reason: String.fromCharCode(cp));
      }
    });
  });

  group('pdf 3.11 Arabic shaper limits', () {
    test('the copied letter table matches the shaper', () {
      for (var cp = 0x0620; cp <= 0x06FF; cp++) {
        final out = pdf_arabic.convert(String.fromCharCodes([0x0628, cp, 0x0628])).runes.toList();
        final shaped = !out.contains(cp) || cp == 0x0621 || cp == 0x0640;
        final claim = PdfUnicodeFonts.pdfShaperSupports(String.fromCharCode(cp));
        if (shaped) {
          expect(claim, isTrue, reason: 'U+${cp.toRadixString(16)} is shaped by pdf');
        } else if (claim) {
          // Only letters that do not join may skip shaping.
          expect(
            (cp >= 0x0660 && cp <= 0x066D) ||
                (cp >= 0x06D6 && cp <= 0x06ED) ||
                (cp >= 0x06F0 && cp <= 0x06F9) ||
                (cp >= 0x064B && cp <= 0x065F) ||
                cp == 0x0670 ||
                cp == 0x06D4 ||
                (cp >= 0x06FD && cp <= 0x06FE),
            isTrue,
            reason: 'U+${cp.toRadixString(16)} joins but pdf leaves it unshaped',
          );
        }
      }
    });

    test('each Sorani letter is outside the shaper except ۆ', () {
      for (final letter in ['ڕ', 'ڵ', 'ێ', 'ە', 'ۊ']) {
        expect(PdfUnicodeFonts.pdfShaperSupports('ب$letterب'), isFalse, reason: letter);
      }
      expect(PdfUnicodeFonts.pdfShaperSupports('ۆ'), isTrue);
      expect(PdfUnicodeFonts.pdfShaperSupports(soraniParagraph), isFalse);
      expect(PdfUnicodeFonts.pdfShaperSupports(arabic), isTrue);
      expect(PdfUnicodeFonts.pdfShaperSupports('$arabic $arabicIndicDigits 2024'), isTrue);
    });

    test('mixed directions are detected', () {
      expect(PdfUnicodeFonts.mixesDirections('$arabic report.pdf'), isTrue);
      expect(PdfUnicodeFonts.mixesDirections('$arabic https://x.y'), isTrue);
      expect(PdfUnicodeFonts.mixesDirections('$arabic ٢٠٢٤ (1)'), isFalse);
      expect(PdfUnicodeFonts.mixesDirections('Hello (world) 42'), isFalse);
    });
  });

  group('PdfUnicodeFonts.pick', () {
    late PdfUnicodeFonts fonts;

    setUpAll(() async {
      fonts = PdfUnicodeFonts();
      await fonts.load();
    });

    test('loads the bundled fonts from the asset bundle', () {
      expect(fonts.arabic, isNotNull);
      expect(fonts.vazir, isNotNull);
      expect(fonts.notoSans, isNotNull);
      expect(fonts.hasRtl, isTrue);
    });

    test('plain Arabic gets a vector font', () {
      expect(fonts.pick(_text(arabic)), isNotNull);
      expect(fonts.pick(_text(arabic, bold: true)), same(fonts.arabicBold));
    });

    test('Sorani is painted, not sent through the pdf shaper', () {
      expect(fonts.pick(_text(soraniParagraph)), isNull);
      expect(fonts.pick(_text(sorani, family: 'Vazirmatn')), isNull);
      expect(
        textExportsAsSearchableVector(
          runCount: 0,
          rotation: 0,
          latin1: false,
          unicodeFontAvailable: fonts.pick(_text(soraniParagraph)) != null,
        ),
        isFalse,
      );
    });

    test('mixed RTL and Latin is painted', () {
      expect(fonts.pick(_text('$arabic invoice.pdf')), isNull);
    });

    test('non-Latin-1 Latin text uses Noto Sans when it is regular weight', () {
      expect(fonts.pick(_text('Kurmancî: şêwe')), same(fonts.notoSans));
      expect(fonts.pick(_text('Kurmancî: şêwe', bold: true)), isNull);
    });

    test('a glyph missing from every font means no vector font', () {
      expect(fonts.pick(_text('$arabic 😀')), isNull);
    });
  });

  group('vector text in a written PDF', () {
    test('a one-line RTL label stays at its position like the preview', () async {
      final fonts = PdfUnicodeFonts();
      await fonts.load();
      const pageW = 600.0;
      const pageH = 800.0;
      final t = _text(arabic)..pos = const Offset(0.1, 0.2);
      expect(fonts.pick(t), isNotNull);
      final doc = pw.Document()
        ..addPage(
          pw.Page(
            pageFormat: const PdfPageFormat(pageW, pageH, marginAll: 0),
            build: (_) => pw.SizedBox(
              width: pageW,
              height: pageH,
              child: pw.Stack(
                children: [const EditorExportService().buildPdfTextForTest(t, pageW, pageH, fonts)],
              ),
            ),
          ),
        );
      final words = const PdfContentTextExtractor().extract(await doc.save())[0] ?? const [];
      expect(words, isNotEmpty);
      final left = words.map((w) => w.rect.left).reduce((a, b) => a < b ? a : b);
      final right = words.map((w) => w.rect.right).reduce((a, b) => a > b ? a : b);
      // Anchored at x = 0.1 and shrink-wrapped, not pushed to the right edge.
      expect(left, closeTo(0.1, 0.02));
      expect(right, lessThan(0.6));
    });

    test('Arabic and Noto Sans text can be extracted again', () async {
      final fonts = PdfUnicodeFonts();
      await fonts.load();
      final doc = pw.Document();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Column(
            children: [
              pw.Text(arabic, textDirection: pw.TextDirection.rtl, style: pw.TextStyle(font: fonts.arabic, fontSize: 18)),
              pw.Text('Kurmancî şêwe', style: pw.TextStyle(font: fonts.notoSans, fontSize: 18)),
            ],
          ),
        ),
      );
      final bytes = await doc.save();
      final pages = const PdfContentTextExtractor().extract(bytes);
      final text = (pages[0] ?? const []).map((e) => e.text).join(' ');
      expect(text, contains('Kurmancî'));
      expect(text, contains('şêwe'));
      // pdf writes presentation forms. Folding them back gives the words.
      final folded = _foldArabicPresentationForms(text);
      expect(folded, contains('مرحبا'));
      expect(folded, contains('بالعالم'));
    });
  });
}

/// Map Arabic presentation forms back to base letters for this check only.
String _foldArabicPresentationForms(String text) {
  // Tatweel (U+0640) joins on both sides and is never replaced, so every
  // presentation form in these outputs belongs to [cp].
  final table = <int, int>{};
  for (var cp = 0x0621; cp <= 0x064A; cp++) {
    for (final probe in [
      String.fromCharCode(cp),
      String.fromCharCodes([0x0640, cp]),
      String.fromCharCodes([cp, 0x0640]),
      String.fromCharCodes([0x0640, cp, 0x0640]),
    ]) {
      for (final form in pdf_arabic.convert(probe).runes) {
        if (form >= 0xFB50) table.putIfAbsent(form, () => cp);
      }
    }
  }
  // Lam-alef ligature.
  table[0xFEFB] = 0x0644;
  table[0xFEFC] = 0x0644;
  final out = StringBuffer();
  for (final cp in text.runes) {
    if (cp == 0xFEFB || cp == 0xFEFC) {
      out.write('لا');
      continue;
    }
    out.writeCharCode(table[cp] ?? cp);
  }
  // Extraction may return RTL glyph runs in visual order.
  final s = out.toString();
  return '$s ${String.fromCharCodes(s.runes.toList().reversed)}';
}
