import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/form_field_builder.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/domain/entities/form_field_annotation.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_form_field_dialogs.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_form_field_properties.dart';

/// A one-page 600 × 800 PDF whose form has the given field dictionaries
/// (each also its widget). [formQ] sets the form-wide /Q.
Uint8List formPdf(List<String> fields, {String formQ = ''}) {
  final first = 4; // fields start at object 4
  final refs = [for (var i = 0; i < fields.length; i++) '${first + i} 0 R'].join(' ');
  final objs = [
    '<< /Type /Catalog /Pages 2 0 R /AcroForm << /Fields [$refs] $formQ >> >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 600 800] /Annots [$refs] >>',
    for (final f in fields) '<< /Type /Annot /Subtype /Widget /P 3 0 R $f >>',
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

Widget app(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  // Left column, right column, then a row lower down: reading order is
  // a, b, c whatever order the form lists them in.
  final form = AcroFormSnapshot.read(formPdf([
    '/FT /Tx /T (c) /Rect [50 500 250 520] /Ff 2',
    '/FT /Tx /T (b) /Rect [300 700 500 720] /Q 2',
    '/FT /Tx /T (a) /Rect [50 702 250 722]',
    '/FT /Btn /T (tick) /Rect [50 600 62 612] /Ff 2',
    '/FT /Tx /T (locked) /Rect [50 400 250 420] /Ff 3',
  ], formQ: '/Q 1'));
  final byName = {for (final f in form.fields) f.name: f};

  test('required flag and alignment are read, with the form-wide default', () {
    expect(byName['c']!.required, isTrue);
    expect(byName['a']!.required, isFalse);
    expect(byName['b']!.quadding, 2, reason: 'its own /Q');
    expect(byName['a']!.quadding, 1, reason: 'the form /Q');
  });

  test('empty required fields: filled ones, read-only ones and other pages do not count', () {
    expect(emptyRequiredFields(form, const {}, [0]).map((f) => f.name), ['c', 'tick']);
    expect(emptyRequiredFields(form, const {'c': 'x', 'tick': 'Yes'}, [0]), isEmpty);
    expect(emptyRequiredFields(form, const {}, const []), isEmpty, reason: 'page not exported');
  });

  test('fill order runs row by row, left to right, text and choice fields only', () {
    final order = fillOrder(form, (source) => source == 0 ? 0 : -1);
    expect(order.map((e) => e.$1.name), ['a', 'b', 'c']);
  });

  test('a centred or right-aligned value is placed inside the box', () {
    String content(int q) => latin1.decode(textAppearance('Hi', 200, 20, 10, quadding: q)!);
    final w = helveticaWidth('Hi', 10);
    expect(w, closeTo((722 + 222) / 100, 1e-9));
    expect(content(0), contains('2 '));
    expect(content(1), contains('${PdfNum.of((200 - w) / 2).raw} '));
    expect(content(2), contains('${PdfNum.of(200 - 2 - w).raw} '));
  });

  test('field names are made unique against the form', () {
    expect(uniqueFieldName('name', {'name'}), 'name_2');
    expect(uniqueFieldName('name', {'name', 'name_2'}), 'name_3');
    expect(uniqueFieldName('addr', {'addr.street'}), 'addr_2', reason: 'a parent name is taken too');
    expect(uniqueFieldName('a.b', {}), 'a_b');
    expect(uniqueFieldName('  ', {}), 'Field');
  });

  test('a placed field survives saving and loading', () {
    final f = FormFieldAnnotation(
      pos: const Offset(0.1, 0.2),
      width: 0.3,
      height: 0.04,
      fieldKind: FormFieldKind.combobox,
      label: 'Plan',
      value: 'Pro',
      options: const ['Basic', 'Pro'],
      required: true,
    );
    final back = annotationFromJson(jsonDecode(jsonEncode(annotationToJson(f))) as Map<String, dynamic>)!
        as FormFieldAnnotation;
    expect(back.fieldKind, FormFieldKind.combobox);
    expect(back.label, 'Plan');
    expect(back.value, 'Pro');
    expect(back.options, ['Basic', 'Pro']);
    expect(back.required, isTrue);
    expect(back.bounds, f.bounds);
  });

  testWidgets('the text dialog offers previous and next and keeps what was typed', (tester) async {
    FormTextResult? result;
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () async => result = await showFormTextDialog(
          context,
          field: byName['b']!,
          initial: '',
          hasPrevious: true,
          hasNext: true,
        ),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'typed');
    await tester.tap(find.byTooltip('Next field'));
    await tester.pumpAndSettle();
    expect(result, (value: 'typed', step: 1));
  });

  testWidgets('field properties: name, required and drop-down options', (tester) async {
    final field = newFormField(FormFieldKind.combobox, label: 'List 1');
    bool? saved;
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () async => saved = await showFormFieldPropertiesDialog(context, field),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('fieldName')), 'Size');
    await tester.enterText(find.byKey(const ValueKey('fieldOptions')), 'S\nM\n\nL');
    await tester.tap(find.text('Required'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(field.label, 'Size');
    expect(field.options, ['S', 'M', 'L']);
    expect(field.required, isTrue);
  });

  testWidgets('cancelling the properties leaves the field unchanged', (tester) async {
    final field = newFormField(FormFieldKind.text, label: 'Text 1');
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () => showFormFieldPropertiesDialog(context, field),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('fieldName')), 'Changed');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(field.label, 'Text 1');
  });
}
