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
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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
            tooltip: 'Paste',
            onPressed: canPaste ? onPaste : null,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: l10n.export,
            onPressed: loading ? null : onExport,
          ),
        ],
      ],
    );
  }
}

class EditorPageNavigation extends StatelessWidget {
  final int currentPage;
  final int pageCount;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const EditorPageNavigation({
    super.key,
    required this.currentPage,
    required this.pageCount,
    this.onPrev,
    this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 100),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FloatingActionButton.small(
            heroTag: 'prev',
            onPressed: currentPage > 0 ? onPrev : null,
            child: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 12),
          FloatingActionButton.small(
            heroTag: 'next',
            onPressed: currentPage < pageCount - 1 ? onNext : null,
            child: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
