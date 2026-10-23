import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Actions the editor runs from a hardware keyboard (tablets, ChromeOS).
enum EditorShortcut {
  undo,
  redo,
  copy,
  paste,
  duplicate,
  delete,
  deselect,
  previousPage,
  nextPage,
  firstPage,
  lastPage,
  find,
  save,
  fitPage,
  help,
}

/// The shortcut for a key press, or null. [control] is Ctrl, or ⌘ on Apple
/// keyboards. Plain letters are never shortcuts, so typing is never taken.
EditorShortcut? editorShortcutFor(LogicalKeyboardKey key, {required bool control, required bool shift}) {
  if (control) {
    return switch (key) {
      LogicalKeyboardKey.keyZ => shift ? EditorShortcut.redo : EditorShortcut.undo,
      LogicalKeyboardKey.keyY => EditorShortcut.redo,
      LogicalKeyboardKey.keyC => EditorShortcut.copy,
      LogicalKeyboardKey.keyV => EditorShortcut.paste,
      LogicalKeyboardKey.keyD => EditorShortcut.duplicate,
      LogicalKeyboardKey.keyF => EditorShortcut.find,
      LogicalKeyboardKey.keyS => EditorShortcut.save,
      LogicalKeyboardKey.digit0 || LogicalKeyboardKey.numpad0 => EditorShortcut.fitPage,
      LogicalKeyboardKey.slash => EditorShortcut.help,
      LogicalKeyboardKey.home => EditorShortcut.firstPage,
      LogicalKeyboardKey.end => EditorShortcut.lastPage,
      _ => null,
    };
  }
  if (shift) return null;
  return switch (key) {
    LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace => EditorShortcut.delete,
    LogicalKeyboardKey.escape => EditorShortcut.deselect,
    LogicalKeyboardKey.pageUp => EditorShortcut.previousPage,
    LogicalKeyboardKey.pageDown => EditorShortcut.nextPage,
    LogicalKeyboardKey.home => EditorShortcut.firstPage,
    LogicalKeyboardKey.end => EditorShortcut.lastPage,
    _ => null,
  };
}

/// Whether keys should go to a text field instead of the editor: one is
/// focused (Delete must delete a character, not the selected mark).
bool textInputHasFocus() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget is EditableText) return true;
  return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// Keys shown in the help sheet, in display order.
const editorShortcutKeys = <EditorShortcut, String>{
  EditorShortcut.undo: 'Ctrl+Z',
  EditorShortcut.redo: 'Ctrl+Shift+Z / Ctrl+Y',
  EditorShortcut.copy: 'Ctrl+C',
  EditorShortcut.paste: 'Ctrl+V',
  EditorShortcut.duplicate: 'Ctrl+D',
  EditorShortcut.delete: 'Delete',
  EditorShortcut.deselect: 'Esc',
  EditorShortcut.previousPage: 'Page Up',
  EditorShortcut.nextPage: 'Page Down',
  EditorShortcut.firstPage: 'Home',
  EditorShortcut.lastPage: 'End',
  EditorShortcut.find: 'Ctrl+F',
  EditorShortcut.save: 'Ctrl+S',
  EditorShortcut.fitPage: 'Ctrl+0',
  EditorShortcut.help: 'Ctrl+/',
};
