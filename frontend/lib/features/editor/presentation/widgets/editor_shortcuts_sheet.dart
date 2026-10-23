import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/application/editor_keyboard_shortcuts.dart';

/// Lists the editor's keyboard shortcuts.
Future<void> showEditorShortcutsSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  String label(EditorShortcut s) => switch (s) {
        EditorShortcut.undo => l10n.undo,
        EditorShortcut.redo => l10n.redo,
        EditorShortcut.copy => l10n.copy,
        EditorShortcut.paste => l10n.shortcutPaste,
        EditorShortcut.duplicate => l10n.duplicate,
        EditorShortcut.delete => l10n.delete,
        EditorShortcut.deselect => l10n.shortcutDeselect,
        EditorShortcut.previousPage => l10n.shortcutPreviousPage,
        EditorShortcut.nextPage => l10n.shortcutNextPage,
        EditorShortcut.firstPage => l10n.shortcutFirstPage,
        EditorShortcut.lastPage => l10n.shortcutLastPage,
        EditorShortcut.find => l10n.shortcutFind,
        EditorShortcut.save => l10n.export,
        EditorShortcut.fitPage => l10n.shortcutFitPage,
        EditorShortcut.help => l10n.shortcutHelp,
      };
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(l10n.shortcutHelp, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final e in editorShortcutKeys.entries)
              ListTile(
                dense: true,
                title: Text(label(e.key)),
                trailing: Text(
                  e.value,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
