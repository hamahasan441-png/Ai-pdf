import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/editor_existing_text_service.dart';
import 'package:ai_pdf/features/editor/data/editor_text_runs.dart';
import 'package:ai_pdf/features/editor/data/pdf_content_text_extractor.dart';
import 'package:ai_pdf/features/editor/data/text_block_service.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_rich_text_toolbar.dart';

/// A word on a 600 × 800 pt page, from pt coordinates.
PdfTextElement w(String text, double x, double y, {double width = 40, double h = 12}) => PdfTextElement(
      text: text,
      rect: Rect.fromLTWH(x / 600, y / 800, width / 600, h / 800),
      fontSize: h,
    );

void main() {
  const service = TextBlockService();
  const aspect = 600 / 800;

  List<String> texts(List<PdfTextElement> words) => [
        for (final b in service.blocks(words, aspect: aspect)) [for (final l in b.lines) l.map((i) => words[i].text).join(' ')].join(' | '),
      ];

  test('lines close together with the same left edge are one paragraph', () {
    final words = [
      w('third', 50, 132), w('line', 95, 132), // listed out of order on purpose
      w('First', 50, 100), w('line', 95, 100), w('here', 140, 100),
      w('second', 50, 116), w('line', 95, 116),
      w('Next', 50, 200), w('paragraph', 95, 200), // a blank line above it
    ];
    expect(texts(words), ['First line here | second line | third line', 'Next paragraph']);
    final block = service.blocks(words, aspect: aspect).first;
    expect(block.linePitch, closeTo(16 / 800, 1e-9));
  });

  test('a wide gap splits a line into columns; columns are separate blocks', () {
    final words = [
      w('Name', 50, 100), w('Hama', 300, 100),
      w('City', 50, 116), w('Erbil', 300, 116),
    ];
    expect(texts(words), ['Name | City', 'Hama | Erbil']);
  });

  test('a much larger heading is not merged into the text under it', () {
    final words = [
      w('Heading', 50, 80, h: 24),
      w('Body', 50, 106), w('text', 95, 106),
    ];
    expect(texts(words), ['Heading', 'Body text']);
  });

  test('right-to-left lines read from right to left', () {
    final words = [w('دوو', 100, 100), w('یەک', 150, 100)];
    expect(texts(words), ['یەک دوو']);
  });

  test('the fixture invoice lines stay separate paragraphs', () {
    final page = const PdfContentTextExtractor().extract(File('test/fixtures/pdf/edit_text.pdf').readAsBytesSync())[0]!;
    final got = [
      for (final b in service.blocks(page, aspect: 595 / 842)) b.words.map((i) => page[i].text).join(' '),
    ];
    expect(got, containsAll(['Invoice number 12345 due today', 'Total amount 999 EUR']));
  });

  test('a paragraph draft flows into one text with the paragraph width and spacing', () {
    final words = [
      w('First', 50, 100), w('line', 95, 100), w('here', 140, 100),
      w('second', 50, 116), w('line', 95, 116),
    ];
    final block = service.blocks(words, aspect: aspect).single;
    final draft = const EditorExistingTextService().draftForWords(
      [for (final i in block.words) words[i]],
      pageHeightPt: 800,
      reflow: true,
      linePitch: block.linePitch,
    );
    expect(draft.textBox.text, 'First line here second line');
    expect(draft.textBox.width, closeTo(block.rect.width, 1e-9));
    expect(draft.textBox.lineHeight, closeTo(16 / 12, 1e-6));
    expect(draft.whiteout.metadata[eraseTextKey], isTrue);

    // A single line keeps its natural width: a longer word must not wrap.
    final one = const EditorExistingTextService().draftForWords([words[0]], pageHeightPt: 800, reflow: true);
    expect(one.textBox.width, isNull);
  });

  group('fixed-width text box', () {
    final box = TextAnnotation(const Offset(0.1, 0.1), 'one two three four five six', Colors.black, 0.02, false, width: 0.3);

    test('lays out exactly its width on every surface', () {
      final layout = AnnotationTextLayout.of(box, const Size(600, 800));
      expect(layout.minWidth, 180);
      expect(layout.maxWidth, 180);
      final free = AnnotationTextLayout.of(TextAnnotation(const Offset(0.1, 0.1), 'x', Colors.black, 0.02, false), const Size(600, 800));
      expect(free.minWidth, 0);
      expect(free.maxWidth, 540);
    });

    test('resizing changes the width and keeps the font size', () {
      final b = box.clone(id: box.id);
      b.scaleTo(const Rect.fromLTWH(0.1, 0.1, 0.5, 0.2));
      expect(b.width, closeTo(0.5, 1e-9));
      expect(b.size, 0.02);
      expect(b.bounds.width, closeTo(0.5, 1e-9));
    });
  });

  testWidgets('the formatting bar applies whole-box styles and shows them', (tester) async {
    final box = TextAnnotation(const Offset(0.1, 0.1), 'Hi', Colors.black, 0.02, true, textAlign: TextAlign.center);
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Stack(children: [
          EditorRichTextToolbar(
            hasFocus: true,
            hasSelection: false,
            box: box,
            onBold: () => calls.add('bold'),
            onItalic: () => calls.add('italic'),
            onUnderline: () => calls.add('underline'),
            onColor: () => calls.add('color'),
            onFont: (f) => calls.add('font:$f'),
            onSizeStep: (d) => calls.add('size:$d'),
            onAlign: (a) => calls.add('align:${a.name}'),
            onToggleRtl: () => calls.add('rtl'),
            onLineHeight: (v) => calls.add('line:$v'),
            onToggleWrap: () => calls.add('wrap'),
          ),
        ]),
      ),
    ));
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.format_bold)).isSelected, isTrue);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.format_align_center)).isSelected, isTrue);
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.format_italic)).isSelected, isFalse);
    await tester.tap(find.byTooltip('Align right'));
    await tester.tap(find.byTooltip('Larger text'));
    await tester.tap(find.byTooltip('Font'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serif').last);
    await tester.pumpAndSettle();
    expect(calls, ['align:right', 'size:1', 'font:serif']);
  });
}
