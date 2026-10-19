import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/form_fill_smarts.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/acro_form_layer.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/form_fill_bar.dart';

/// A one-page 600 × 800 PDF whose form has the given field dictionaries.
Uint8List formPdf(List<String> fields, {List<String> extra = const []}) {
  final refs = [for (var i = 0; i < fields.length; i++) '${4 + i} 0 R'].join(' ');
  final objs = [
    '<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [$refs] >> >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Annots [$refs] >>',
    for (final f in fields) '<< /Type /Annot /Subtype /Widget /P 3 0 R $f >>',
    ...extra,
  ];
  final b = StringBuffer('%PDF-1.7\n');
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

PdfTextElement word(String text, double l, double t, double r, double b) =>
    PdfTextElement(text: text, rect: Rect.fromLTRB(l, t, r, b), fontSize: 9);

void main() {
  const smarts = FormFillSmarts();

  group('what a field asks for', () {
    final form = AcroFormSnapshot.read(formPdf(
      [
        // Acrobat's own date format script, as a string and as a stream.
        '/FT /Tx /T (d1) /Rect [10 10 100 20] /AA << /F << /S /JavaScript /JS (AFDate_FormatEx\\("dd.mm.yyyy"\\);) >> >>',
        '/FT /Tx /T (n1) /Rect [10 30 100 40] /AA << /K << /S /JavaScript /JS 15 0 R >> >>', // the stream after the 11 fields
        '/FT /Tx /T (zip) /Rect [10 50 100 60] /AA << /F << /S /JavaScript /JS (AFSpecial_Format\\(0\\);) >> >>',
        '/FT /Tx /T (txtGeburtsdatum) /TU (Geburtsdatum) /Rect [10 70 100 80]',
        '/FT /Tx /T (Telefon) /Rect [10 90 100 100]',
        '/FT /Tx /T (Mail) /Rect [10 110 100 120]',
        '/FT /Tx /T (Bemerkung) /Rect [10 130 100 160] /Ff 4096',
        '/FT /Tx /T (Vorname) /Rect [10 170 100 180]',
        '/FT /Tx /T (OrtDatum) /TU (Ort, Datum) /Rect [10 190 100 200]',
        '/FT /Tx /T (pob) /TU (Place of birth) /Rect [10 210 100 220]',
        '/FT /Tx /T (Exportdatum) /Rect [10 230 100 240]',
      ],
      extra: ['<< /Length 30 >>\nstream\nAFNumber_Keystroke(2, 0, 0, 0);\nendstream'],
    ));
    final f = {for (final x in form.fields) x.name: x};

    test('format scripts are read', () {
      expect(f['d1']!.format, AcroValueFormat.date);
      expect(f['d1']!.datePattern, 'dd.mm.yyyy');
      expect(f['n1']!.format, AcroValueFormat.number, reason: 'script in a stream');
      expect(f['zip']!.format, AcroValueFormat.zip);
      expect(f['txtGeburtsdatum']!.alternateName, 'Geburtsdatum');
    });

    test('the keyboard and mask follow the field', () {
      final d1 = smarts.of(f['d1']!);
      expect(d1.input, FieldInput.date);
      expect(d1.datePattern, 'dd.MM.yyyy', reason: 'Acrobat m (month) is intl M');
      expect(smarts.of(f['n1']!).keyboard, const TextInputType.numberWithOptions(decimal: true));
      expect(smarts.of(f['txtGeburtsdatum']!).input, FieldInput.date);
      expect(smarts.of(f['txtGeburtsdatum']!).label, 'Geburtsdatum');
      expect(smarts.of(f['Telefon']!).input, FieldInput.phone);
      expect(smarts.of(f['Mail']!).input, FieldInput.email);
      expect(smarts.of(f['Bemerkung']!).input, FieldInput.multiline);
      expect(smarts.of(f['Vorname']!).input, FieldInput.text);
      // A place goes in these too: letters must be typable.
      expect(smarts.of(f['OrtDatum']!).input, FieldInput.text);
      expect(smarts.of(f['pob']!).input, FieldInput.text);
      expect(smarts.of(f['Exportdatum']!).input, FieldInput.date, reason: '"ort" inside a word is not a place');
    });

    test('the printed label above a field names it and sets its date pattern', () {
      // "3 Geburtsdatum (TT.MM.JJJJ)" printed just above the field.
      const rect = Rect.fromLTRB(0.05, 0.30, 0.45, 0.33);
      final words = [
        word('3', 0.05, 0.27, 0.06, 0.29),
        word('Geburtsdatum', 0.07, 0.27, 0.18, 0.29),
        word('(TT.MM.JJJJ)', 0.19, 0.27, 0.28, 0.29),
        word('Nachname', 0.55, 0.27, 0.65, 0.29), // above the next field, not this one
        word('Other', 0.05, 0.10, 0.12, 0.12), // far above
      ];
      final s = smarts.of(f['Vorname']!, rect: rect, words: words);
      expect(s.label, 'Geburtsdatum (TT.MM.JJJJ)');
      expect(s.input, FieldInput.date);
      expect(s.datePattern, 'dd.MM.yyyy');
    });

    test('a label to the left on the same line is used when nothing is above', () {
      const rect = Rect.fromLTRB(0.3, 0.50, 0.6, 0.52);
      final words = [word('PLZ:', 0.2, 0.50, 0.28, 0.52)];
      final s = smarts.of(f['Vorname']!, rect: rect, words: words);
      expect(s.label, 'PLZ:');
      expect(s.input, FieldInput.zip);
    });
  });

  test('typing a date puts the separators in', () {
    final mask = DateMaskFormatter('dd.MM.yyyy');
    TextEditingValue type(String before, String after) =>
        mask.formatEditUpdate(TextEditingValue(text: before), TextEditingValue(text: after));
    expect(type('', '1').text, '1');
    expect(type('1', '12').text, '12.');
    expect(type('12.', '12.0').text, '12.0');
    expect(type('12.0', '12.03').text, '12.03.');
    expect(type('12.03.', '12.03.20261').text, '12.03.2026', reason: 'no more digits than the pattern');
    expect(type('', 'Berlin, 1').text, 'Berlin, 1', reason: 'letters are kept: not only a date');
    expect(type('12.', '12').text, '12', reason: 'deleting the separator is allowed');
    expect(DateMaskFormatter('d. MMMM yyyy').usable, isFalse);
  });

  group('the form on the page', () {
    final form = AcroFormSnapshot.read(formPdf([
      '/FT /Tx /T (name) /Rect [50 700 250 720]',
      '/FT /Btn /T (ok) /Rect [50 650 62 662] /AP << /N << /Yes 1 0 R /Off 1 0 R >> >>',
    ]));
    final placed = [
      for (final f in form.fields)
        for (final w in f.widgets) (field: f, widget: w, rect: form.rectOf(w)),
    ];

    Widget layer({AcroInlineEditing? editing, String? focus, int? obj, void Function(AcroField, AcroWidget)? onTap}) =>
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 800,
              child: AcroFormLayer(
                widgets: placed,
                edits: const {},
                interactive: true,
                onTap: onTap ?? (_, __) {},
                focusName: focus,
                focusObjNum: obj,
                editing: editing,
              ),
            ),
          ),
        );

    testWidgets('a text field being filled takes typing right in its box', (tester) async {
      tester.view.physicalSize = const Size(600, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = TextEditingController(text: 'Ha');
      final node = FocusNode();
      final name = placed.first;
      await tester.pumpWidget(layer(
        focus: 'name',
        obj: name.widget.objNum,
        editing: AcroInlineEditing(
          fieldName: 'name',
          widgetObjNum: name.widget.objNum,
          controller: controller,
          focusNode: node,
          keyboard: TextInputType.text,
          onSubmitted: (_) {},
        ),
      ));
      final box = tester.getRect(find.byType(TextField));
      // The field is 200 × 20 pt at 50, 80 from the top, on a page shown 1:1.
      expect(box.left, greaterThanOrEqualTo(50));
      expect(box.right, lessThanOrEqualTo(250));
      expect(box.top, greaterThanOrEqualTo(80));
      expect(box.bottom, lessThanOrEqualTo(100));
      await tester.enterText(find.byType(TextField), 'Hama');
      expect(controller.text, 'Hama');
    });

    testWidgets('tapping a check box reports it', (tester) async {
      AcroField? tapped;
      await tester.pumpWidget(layer(onTap: (f, _) => tapped = f));
      await tester.tapAt(tester.getCenter(find.bySemanticsLabel(RegExp('ok'))));
      expect(tapped?.name, 'ok');
    });
  });

  testWidgets('the fill bar: previous, next, reset and done', (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        bottomNavigationBar: FormFillBar(
          label: 'Vorname',
          required: true,
          onPrevious: null,
          onNext: () => calls.add('next'),
          onReset: () => calls.add('reset'),
          onDone: () => calls.add('done'),
        ),
      ),
    ));
    expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.arrow_back)).onPressed, isNull);
    await tester.tap(find.byTooltip('Next field'));
    await tester.tap(find.text('Reset'));
    await tester.tap(find.text('Done'));
    expect(calls, ['next', 'reset', 'done']);
    expect(find.text('Vorname *'), findsOneWidget);
  });
}
