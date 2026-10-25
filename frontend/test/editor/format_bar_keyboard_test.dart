import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_rich_text_toolbar.dart';

void main() {
  TextAnnotation box() => TextAnnotation(Offset.zero, 'Hi', Colors.red, 0.03, false);

  Future<double> bottom(WidgetTester tester, double keyboard) async {
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)).copyWith(
          viewInsets: EdgeInsets.only(bottom: keyboard),
          padding: const EdgeInsets.only(bottom: 20),
        ),
        child: Stack(
          children: [
            EditorRichTextToolbar(
              hasFocus: true,
              hasSelection: false,
              box: box(),
              onBold: () {},
              onItalic: () {},
              onUnderline: () {},
              onColor: () {},
            ),
          ],
        ),
      ),
    ));
    return tester.widget<Positioned>(find.byType(Positioned).first).bottom!;
  }

  testWidgets('the format bar sits on the keyboard while new text is typed', (tester) async {
    expect(await bottom(tester, 0), 0);
    expect(await bottom(tester, 320), 328);
    expect(find.byTooltip('Text colour'), findsOneWidget);
  });
}
