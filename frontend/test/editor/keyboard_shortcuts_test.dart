import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/application/editor_keyboard_shortcuts.dart';

void main() {
  EditorShortcut? k(LogicalKeyboardKey key, {bool ctrl = false, bool shift = false}) =>
      editorShortcutFor(key, control: ctrl, shift: shift);

  test('the usual editor keys', () {
    expect(k(LogicalKeyboardKey.keyZ, ctrl: true), EditorShortcut.undo);
    expect(k(LogicalKeyboardKey.keyZ, ctrl: true, shift: true), EditorShortcut.redo);
    expect(k(LogicalKeyboardKey.keyY, ctrl: true), EditorShortcut.redo);
    expect(k(LogicalKeyboardKey.keyS, ctrl: true), EditorShortcut.save);
    expect(k(LogicalKeyboardKey.delete), EditorShortcut.delete);
    expect(k(LogicalKeyboardKey.backspace), EditorShortcut.delete);
    expect(k(LogicalKeyboardKey.pageDown), EditorShortcut.nextPage);
    expect(k(LogicalKeyboardKey.escape), EditorShortcut.deselect);
  });

  test('plain letters and shifted keys are never shortcuts', () {
    for (final key in [LogicalKeyboardKey.keyT, LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyZ, LogicalKeyboardKey.space]) {
      expect(k(key), isNull, reason: key.debugName);
      expect(k(key, shift: true), isNull);
    }
    expect(k(LogicalKeyboardKey.delete, shift: true), isNull);
  });

  test('every shortcut has a help line', () {
    expect(editorShortcutKeys.keys.toSet(), EditorShortcut.values.toSet());
  });

  testWidgets('a focused text field gets Delete; the editor gets it otherwise', (tester) async {
    final handled = <EditorShortcut>[];
    final field = TextEditingController(text: 'abc');
    addTearDown(field.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Focus(
        autofocus: true,
        onKeyEvent: (node, e) {
          if (e is! KeyDownEvent || textInputHasFocus()) return KeyEventResult.ignored;
          final s = editorShortcutFor(e.logicalKey, control: false, shift: false);
          if (s == null) return KeyEventResult.ignored;
          handled.add(s);
          return KeyEventResult.handled;
        },
        child: Scaffold(body: TextField(controller: field)),
      ),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    expect(handled, [EditorShortcut.delete], reason: 'nothing focused: the editor acts');

    await tester.tap(find.byType(TextField));
    await tester.pump();
    field.selection = const TextSelection.collapsed(offset: 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(handled, [EditorShortcut.delete], reason: 'typing is not taken');
    expect(field.text, 'ab');
  });
}
