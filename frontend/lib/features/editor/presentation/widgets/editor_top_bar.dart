import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class EditorTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final int currentPage;
  final int pageCount;
  final bool hasDocument;
  final bool canUndo;
  final bool canRedo;
  final bool canPaste;
  final bool loading;
  final bool unsavedChanges;

  /// Notifies when the document is not saved yet; shown as a quiet dot so
  /// the user always knows whether their work is safe.
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onPaste;
  final VoidCallback? onExport;

  const EditorTopBar({
    super.key,
    required this.title,
    required this.currentPage,
    required this.pageCount,
    required this.hasDocument,
    required this.canUndo,
    required this.canRedo,
    required this.canPaste,
    required this.loading,
    this.unsavedChanges = false,
    this.onUndo,
    this.onRedo,
    this.onPaste,
    this.onExport,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return AppBar(
      titleSpacing: 16,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unsavedChanges) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: l10n.unsavedChangesDot,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColorsDot.of(context),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (pageCount > 0)
            Text(
              l10n.pageOfPages(currentPage + 1, pageCount),
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
        ],
      ),
      actions: [
        if (hasDocument) ...[
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: l10n.undo,
            onPressed: canUndo ? onUndo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: l10n.redo,
            onPressed: canRedo ? onRedo : null,
          ),
          IconButton(
            icon: const Icon(Icons.content_paste),
            tooltip: l10n.shortcutPaste,
            onPressed: canPaste ? onPaste : null,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(
              onPressed: loading ? null : onExport,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: const Icon(Icons.ios_share, size: 17),
              label: Text(l10n.export),
            ),
          ),
        ],
      ],
    );
  }
}

/// The unsaved-changes dot colour: the calm accent in both themes.
class AppColorsDot {
  static Color of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF63CFC2)
          : const Color(0xFF2BB5A6);
}
