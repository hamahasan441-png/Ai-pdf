import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_pdf/features/editor/presentation/widgets/editor_text_color_picker_sheet.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_toolbar.dart';

void main() {
  test('hex parsing accepts the usual forms and rejects the rest', () {
    expect(parseHex('#1E88E5'), const Color(0xFF1E88E5));
    expect(parseHex('1e88e5'), const Color(0xFF1E88E5));
    expect(parseHex('#abc'), const Color(0xFFAABBCC));
    expect(parseHex('#801E88E5'), const Color(0x801E88E5));
    for (final bad in ['', '#', '#12', '#12345', 'zzzzzz', '#1E88E5FF00', 'red']) {
      expect(parseHex(bad), isNull, reason: bad);
    }
    expect(toHex(const Color(0xFF1E88E5)), '#1E88E5');
    expect(toHex(const Color(0x801E88E5)), '#801E88E5');
    expect(parseHex(toHex(const Color(0xFF00000A))), const Color(0xFF00000A));
  });

  test('recent colours: newest first, no duplicates, at most eight', () {
    var list = <Color>[];
    for (var i = 0; i < 10; i++) {
      list = RecentColors.pushed(list, Color(0xFF000000 + i));
    }
    list = RecentColors.pushed(list, const Color(0xFF000005));
    expect(list.length, RecentColors.max);
    expect(list.first, const Color(0xFF000005));
    expect(list.where((c) => c == const Color(0xFF000005)), hasLength(1));
  });

  test('the toolbar keeps a picked colour one tap away', () {
    const teal = Color(0xFF00897B);
    const pink = Color(0xFFD81B60);
    const brown = Color(0xFF6D4C41);
    expect(EditorToolbar.quickColors(Colors.red, const []), EditorToolbar.presets);
    expect(EditorToolbar.quickColors(teal, const [pink, brown]).skip(5), [teal]);
    expect(EditorToolbar.quickColors(Colors.blue, const [pink, Colors.red, brown]).skip(5), [pink]);
  });

  testWidgets('a hex colour can be typed, and a wrong one is explained', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Color? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => result = await showEditorTextColorPickerSheet(context, selectedColor: Colors.black),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(find.textContaining('#RRGGBB'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.byType(TextField), '#1E88E5');
    await tester.tap(find.text('Use'));
    await tester.pumpAndSettle();
    expect(result, const Color(0xFF1E88E5));
    expect(RecentColors.current.first, const Color(0xFF1E88E5));
  });
}
