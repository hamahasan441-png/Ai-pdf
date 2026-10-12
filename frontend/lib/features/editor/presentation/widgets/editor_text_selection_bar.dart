import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';

/// Shown after the user drags across real PDF words (Select tool).
/// Copy, or turn the selection into a Foxit-style text mark.
class EditorTextSelectionBar extends StatelessWidget {
  final ValueChanged<EditTool> onMarkup;
  final VoidCallback onCopy;
  final VoidCallback onClose;

  const EditorTextSelectionBar({
    super.key,
    required this.onMarkup,
    required this.onCopy,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: cs.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: l10n.copy,
              icon: const Icon(Icons.copy),
              onPressed: onCopy,
            ),
            IconButton(
              tooltip: l10n.toolHighlight,
              icon: const Icon(Icons.highlight),
              onPressed: () => onMarkup(EditTool.highlight),
            ),
            IconButton(
              tooltip: l10n.toolUnderline,
              icon: const Icon(Icons.format_underlined),
              onPressed: () => onMarkup(EditTool.underline),
            ),
            IconButton(
              tooltip: l10n.toolStrikeout,
              icon: const Icon(Icons.format_strikethrough),
              onPressed: () => onMarkup(EditTool.strikeout),
            ),
            IconButton(
              tooltip: l10n.toolSquiggly,
              icon: const Icon(Icons.waves),
              onPressed: () => onMarkup(EditTool.squiggly),
            ),
            IconButton(
              tooltip: l10n.deselect,
              icon: const Icon(Icons.close),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
