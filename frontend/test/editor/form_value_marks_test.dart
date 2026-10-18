import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/editor_export_service.dart';
import 'package:ai_pdf/features/editor/data/form_value_marks.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

void main() {
  final form = AcroFormSnapshot.read(File('test/fixtures/pdf/forms.pdf').readAsBytesSync());

  test('edited values become a white box and the value, on the right page', () {
    final marks = formValueMarks(
      form: form,
      edits: const {'name': 'Hama', 'agree': 'Yes', 'size': 'L', 'note': 'x'},
      sourcePages: const [1, 0], // pages swapped in the editor
    );
    final page0 = marks[1]!; // source page 0 is editor page 1 now
    final texts = [for (final m in page0) if (m is TextAnnotation) m.text];
    expect(texts, containsAll(['Hama', '✓', '●']));
    expect(texts.where((t) => t == '●'), hasLength(1), reason: 'only the chosen radio');
    final boxes = page0.whereType<ShapeAnnotation>().toList();
    expect(boxes, hasLength(1 + 1 + 3), reason: 'name, agree and all three radios are covered');
    expect(boxes.every((b) => b.filled && b.type == ShapeType.rect), isTrue);
    expect([for (final m in marks[0]!) if (m is TextAnnotation) m.text], ['x']);

    // The boxes must not make the preserving export flatten the page.
    expect(pagesThatHideContent({1: PageLayer()..items.addAll(page0)}, const [1]), isEmpty);
  });

  test('unchanged and read-only fields get no marks', () {
    expect(formValueMarks(form: form, edits: const {}, sourcePages: const [0, 1]), isEmpty);
    expect(formValueMarks(form: form, edits: const {'id': 'X'}, sourcePages: const [0, 1]), isEmpty);
  });

  test('a turned page moves the boxes with it', () {
    final straight = formValueMarks(form: form, edits: const {'name': 'A'}, sourcePages: const [0]);
    final turned = formValueMarks(form: form, edits: const {'name': 'A'}, sourcePages: const [0], quarterTurns: const {0: 1});
    final a = straight[0]!.whereType<ShapeAnnotation>().single;
    final b = turned[0]!.whereType<ShapeAnnotation>().single;
    // Turned clockwise: the field near the top-left goes to the top-right.
    expect(a.start.dx, lessThan(0.5));
    expect(b.end.dx, greaterThan(0.5));
    expect((b.end.dx - b.start.dx), closeTo(a.end.dy - a.start.dy, 1e-9));
  });
}
