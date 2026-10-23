import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/application/editor_controller.dart';
import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/history/form_value_command.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/acro_form_layer.dart';

void main() {
  final form = AcroFormSnapshot.read(File('test/fixtures/pdf/forms.pdf').readAsBytesSync());
  List<PlacedAcroWidget> page0() => [
        for (final f in form.fields)
          for (final w in f.widgets)
            if (w.pageIndex == 0) (field: f, widget: w, rect: form.rectOf(w)),
      ];

  Future<List<String>> pump(WidgetTester tester, {required bool interactive, Map<String, Object> edits = const {}}) async {
    final tapped = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 595,
          height: 842,
          child: AcroFormLayer(
            widgets: page0(),
            edits: edits,
            interactive: interactive,
            onTap: (f, w) => tapped.add(w.onState == null ? f.name : '${f.name}=${w.onState}'),
          ),
        ),
      ),
    ));
    return tapped;
  }

  Offset centerOf(WidgetTester tester, String name, {int i = 0}) {
    final f = form.fields.firstWhere((f) => f.name == name);
    final r = form.rectOf(f.widgets[i]);
    final box = tester.getRect(find.byType(AcroFormLayer));
    return box.topLeft + Offset(r.center.dx * box.width, r.center.dy * box.height);
  }

  testWidgets('fields show their values and take taps; read-only ones do not', (tester) async {
    final tapped = await pump(tester, interactive: true, edits: const {'name': 'Hama'});
    expect(find.text('Hama'), findsOneWidget, reason: 'the edit replaces the file value');
    expect(find.text('Ada'), findsNothing);
    expect(find.text('ID-7'), findsOneWidget);
    expect(find.text('Iraq'), findsOneWidget, reason: 'a combo shows the option text');
    expect(find.byIcon(Icons.circle), findsOneWidget, reason: 'one radio is selected');

    await tester.tapAt(centerOf(tester, 'name'));
    await tester.tapAt(centerOf(tester, 'id'));
    await tester.tapAt(centerOf(tester, 'size', i: 2));
    expect(tapped, ['name', 'size=L']);
  });

  testWidgets('no taps while a drawing tool is active', (tester) async {
    final tapped = await pump(tester, interactive: false);
    await tester.tapAt(centerOf(tester, 'agree'));
    expect(tapped, isEmpty);
  });

  test('a fill is one undoable step, and saved edits read back', () {
    final c = EditorController();
    addTearDown(c.dispose);
    final values = <String, Object>{};
    final page = PageLayer();
    c.record(FormValueCommand(values, 'name', before: null, after: 'Hama'), page);
    c.record(FormValueCommand(values, 'langs', before: null, after: const ['Kurdish']), page);
    expect(values, {'name': 'Hama', 'langs': ['Kurdish']});
    expect(c.state.hasUnsavedChanges, isTrue);
    c.undo(page);
    expect(values, {'name': 'Hama'});
    c.undo(page);
    expect(values, isEmpty);
    c.redo(page);
    expect(values, {'name': 'Hama'});

    final json = layersToJson(const {}, formValues: const {'name': 'Hama', 'langs': ['Kurdish', 'Arabic']});
    expect(formValuesFromJson(json['forms']), {'name': 'Hama', 'langs': ['Kurdish', 'Arabic']});
    expect(formValuesFromJson({'bad': 3, 'ok': 'x', 'mixed': ['a', 1]}), {'ok': 'x'});
    expect(formValuesFromJson(null), isEmpty);
  });
}
