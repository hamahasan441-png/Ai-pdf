import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';

/// Shown after the user drags across real PDF words (Select tool).
/// Copy, or turn the selection into a Foxit-style text mark.
class EditorTextSelectionBar extends StatelessWidget {
  final ValueChanged<EditTool> onMarkup;
  final VoidCallback onCopy;
  final VoidCallback? onEdit;
  final VoidCallback onClose;

  const EditorTextSelectionBar({
    super.key,
    required this.onMarkup,
    required this.onCopy,
    this.onEdit,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    Widget icon(IconData i, String tip, VoidCallback onTap, {Color? color}) => IconButton(
          tooltip: tip,
          icon: Icon(i, size: 21, color: color ?? cs.onSurface),
          onPressed: onTap,
          constraints: const BoxConstraints.tightFor(width: 42, height: 42),
          padding: EdgeInsets.zero,
        );
    return Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Color(0x261B2130), blurRadius: 22, offset: Offset(0, 8))],
        ),
        child: Material(
          color: cs.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: cs.outlineVariant),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Editing the words is the main action here.
                if (onEdit != null) ...[
                  FilledButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: Text(l10n.editText),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                icon(Icons.copy, l10n.copy, onCopy),
                Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 4), color: cs.outlineVariant),
                icon(Icons.highlight, l10n.toolHighlight, () => onMarkup(EditTool.highlight), color: const Color(0xFFE0A800)),
                icon(Icons.format_underlined, l10n.toolUnderline, () => onMarkup(EditTool.underline)),
                icon(Icons.format_strikethrough, l10n.toolStrikeout, () => onMarkup(EditTool.strikeout)),
                icon(Icons.waves, l10n.toolSquiggly, () => onMarkup(EditTool.squiggly)),
                Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 4), color: cs.outlineVariant),
                icon(Icons.close, l10n.deselect, onClose, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
