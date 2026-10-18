import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/preserving_pdf_writer.dart';

PdfObjectStore forms() => PdfObjectStore.parse(File('test/fixtures/pdf/forms.pdf').readAsBytesSync());

Map<String, AcroField> byName(PdfObjectStore s) => {for (final f in const AcroFormReader().read(s)) f.name: f};

void main() {
  test('reads every kind of field with its value and options', () {
    final f = byName(forms());
    expect(f.keys.toSet(), {'name', 'address', 'id', 'agree', 'size', 'country', 'langs', 'note'});
    expect(f['name']!.kind, AcroFieldKind.text);
    expect(f['name']!.value, 'Ada');
    expect(f['name']!.fontSize, 12);
    expect(f['address']!.multiline, isTrue);
    expect(f['id']!.readOnly, isTrue);
    expect(f['id']!.fillable, isFalse);
    expect(f['agree']!.kind, AcroFieldKind.checkbox);
    expect(f['agree']!.value, 'Off');
    expect(f['agree']!.checkedState, 'Yes');
    expect(f['size']!.kind, AcroFieldKind.radio);
    expect(f['size']!.value, 'M');
    expect([for (final w in f['size']!.widgets) w.onState], ['S', 'M', 'L']);
    expect(f['country']!.combo, isTrue);
    expect(f['country']!.value, 'iq');
    expect(f['country']!.displayOf('de'), 'Germany');
    expect(f['langs']!.multiSelect, isTrue);
    expect(f['langs']!.value, isEmpty);
    expect([for (final o in f['langs']!.options) o.$2], ['Kurdish', 'Arabic', 'English']);
    expect(f['note']!.widgets.single.pageIndex, 1);
    expect(f['name']!.widgets.single.onState, isNull, reason: 'text fields have no on state');
  });

  test('widget positions on the displayed page, also on a turned page', () {
    final s = forms();
    final f = byName(s);
    final name = f['name']!.widgets.single;
    final r = displayRect(name.rect, s.pages[0].cropBox, s.pages[0].rotate);
    // PyMuPDF placed it at (72, 100)–(300, 124) from the top left of A4.
    expect(r.left * 595, closeTo(72, 0.01));
    expect(r.top * 842, closeTo(100, 0.01));
    expect(r.right * 595, closeTo(300, 0.01));
    expect(r.bottom * 842, closeTo(124, 0.01));

    // Same mapping as the overlay matrix the export uses, for every turn.
    for (final rot in [0, 90, 180, 270]) {
      final crop = [10.0, 20.0, 410.0, 620.0];
      final m = overlayMatrix(crop: crop, rotate: rot, formWidth: rot % 180 == 0 ? 400 : 600, formHeight: rot % 180 == 0 ? 600 : 400);
      final shownW = rot % 180 == 0 ? 400.0 : 600.0;
      final shownH = rot % 180 == 0 ? 600.0 : 400.0;
      // Displayed point (0.25, 0.1) from the top left → overlay coordinates
      // (origin bottom left) → user space.
      final ox = 0.25 * shownW, oy = (1 - 0.1) * shownH;
      final ux = m[0] * ox + m[2] * oy + m[4];
      final uy = m[1] * ox + m[3] * oy + m[5];
      final back = displayRect([ux, uy, ux + 0.001, uy + 0.001], crop, rot);
      expect(back.left, closeTo(0.25, 1e-3), reason: 'rotate $rot');
      expect(back.top, closeTo(0.1, 1e-3), reason: 'rotate $rot');
    }
  });

  test('values written by the export read back, and nothing else changes', () {
    final src = forms();
    final writer = PreservingPdfWriter(src, null);
    final out = writer.write(
      const [SourcePageSpec(0), SourcePageSpec(1)],
      formValues: {
        'name': 'Hama Hasan',
        'address': 'Street 1\nSulaymaniyah',
        'agree': 'Yes',
        'size': 'L',
        'country': 'de',
        'langs': ['Kurdish', 'English'],
        'note': 'سڵاو', // not drawable with Helvetica: the viewer draws it
        'id': 'CHANGED', // read only: must stay
        'missing': 'x',
      },
    );
    expect(writer.report!.filledFormFields, 7);
    final back = PdfObjectStore.parse(out);
    final f = byName(back);
    expect(f['name']!.value, 'Hama Hasan');
    expect(f['address']!.value, 'Street 1\nSulaymaniyah');
    expect(f['agree']!.value, 'Yes');
    expect(f['size']!.value, 'L');
    expect(f['country']!.value, 'de');
    expect(f['langs']!.value, ['Kurdish', 'English']);
    expect(f['note']!.value, 'سڵاو');
    expect(f['id']!.value, 'ID-7');

    PdfDict obj(int n) => back.object(n)!.value as PdfDict;
    // Radio and check box widgets show the new state.
    expect([for (final w in f['size']!.widgets) (obj(w.objNum)['/AS'] as PdfName).name], ['/Off', '/Off', '/L']);
    expect((obj(f['agree']!.widgets.single.objNum)['/AS'] as PdfName).name, '/Yes');
    // A new appearance draws the text; the Kurdish one has none, so the
    // reader draws it instead of a stale picture.
    final nameAp = (obj(f['name']!.widgets.single.objNum)['/AP'] as PdfDict)['/N'] as PdfRef;
    expect(latin1.decode(back.decodeStream(back.object(nameAp.num)!)), contains('(Hama Hasan) Tj'));
    expect(obj(f['note']!.widgets.single.objNum)['/AP'], isNull);
    final acro = back.resolve(back.catalog['/AcroForm']) as PdfDict;
    expect((acro['/NeedAppearances'] as PdfBool).value, isTrue);
    expect(back.pages, hasLength(2));
  });

  test('no values: the form is written as it was', () {
    final src = forms();
    final out = PreservingPdfWriter(src, null).write(const [SourcePageSpec(0), SourcePageSpec(1)]);
    final back = PdfObjectStore.parse(out);
    final acro = back.resolve(back.catalog['/AcroForm']) as PdfDict;
    expect(acro['/NeedAppearances'], isNull);
    expect(byName(back)['name']!.value, 'Ada');
  });

  test('text strings round-trip through the hex token', () {
    for (final t in ['plain', 'café', 'سڵاو بۆ هەمووان', 'a(b)c\\', '']) {
      expect(PdfString.ofText(t).text, t);
    }
    expect(latin1.decode(PdfString.ofText('ok').raw), '<6f6b>');
  });

  test('appearance text fits and escapes', () {
    final a = latin1.decode(textAppearance('a (b)', 100, 20, 0)!);
    expect(a, contains(r'(a \(b\)) Tj'));
    expect(textAppearance('سڵاو', 100, 20, 0), isNull);
    final multi = latin1.decode(textAppearance('one\ntwo', 100, 60, 10, multiline: true)!);
    expect(multi, allOf(contains('(one) Tj'), contains('T* (two) Tj')));
    expect(Uint8List(0), isEmpty);
  });
}
