import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/inline_text_editor.dart';

void main() {
  TextAnnotation box(String text) => TextAnnotation(Offset.zero, text, Colors.black, 0.03, false);

  Future<void> pump(WidgetTester tester, InlineTextEditor editor) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 400, height: 600, child: editor),
      ),
    ));
  }

  testWidgets('an empty field shows its label, and a value hides it', (tester) async {
    await pump(
      tester,
      InlineTextEditor(
        annotation: box(''),
        canvasSize: const Size(400, 600),
        hint: 'ئیمەیڵ',
        singleLine: true,
        keyboardType: TextInputType.emailAddress,
        onDone: () {},
        onTextChanged: (_) {},
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.hintText, 'ئیمەیڵ');
    expect(field.maxLines, 1);
    expect(field.textInputAction, TextInputAction.done);
    expect(field.textDirection, TextDirection.rtl);

    await pump(
      tester,
      InlineTextEditor(
        annotation: box('sara@example.com'),
        canvasSize: const Size(400, 600),
        hint: 'ئیمەیڵ',
        keyboardType: TextInputType.multiline,
        onDone: () {},
        onTextChanged: (_) {},
      ),
    );
    final filled = tester.widget<TextField>(find.byType(TextField));
    expect(filled.maxLines, isNull);
    expect(filled.textInputAction, TextInputAction.newline);
    expect(filled.controller!.text, 'sara@example.com');
  });
}
