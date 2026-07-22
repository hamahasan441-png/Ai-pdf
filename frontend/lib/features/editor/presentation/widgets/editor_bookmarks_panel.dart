import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_bookmarks_controller.dart';

/// Panel showing user-created bookmarks/favorites (Phase 44).
///
/// Each row shows the bookmark label, page number, and a color dot. Tap to
/// jump, swipe to delete. The header has an "Add bookmark" quick action for
/// the current page.
class EditorBookmarksPanel extends StatelessWidget {
  final EditorBookmarksState bookmarksState;
  final int currentPage;
  final VoidCallback onAddCurrent;
  final ValueChanged<int> onJumpToPage;
  final ValueChanged<String> onDelete;
  final VoidCallback onClose;

  const EditorBookmarksPanel({
    super.key,
    required this.bookmarksState,
    required this.currentPage,
    required this.onAddCurrent,
    required this.onJumpToPage,
    required this.onDelete,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = bookmarksState.sorted;

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(12),
        bottomLeft: Radius.circular(12),
      ),
      color: cs.surface,
      child: SizedBox(
        width: 260,
        child: Column(
          children: [
            _header(cs),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bookmark_border,
                              size: 40, color: cs.onSurfaceVariant.withOpacity(0.3)),
                          const SizedBox(height: 8),
                          Text('No bookmarks yet',
                              style: TextStyle(color: cs.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _row(items[i], cs),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.bookmarks, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('Bookmarks (${bookmarksState.count})',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          IconButton(
            icon: Icon(
              bookmarksState.isPageBookmarked(currentPage)
                  ? Icons.bookmark
                  : Icons.bookmark_add_outlined,
              size: 18,
            ),
            onPressed: onAddCurrent,
            tooltip: 'Bookmark this page',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _row(EditorBookmark bookmark, ColorScheme cs) {
    final isActive = bookmark.pageIndex == currentPage;
    return Dismissible(
      key: ValueKey(bookmark.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(bookmark.id),
      background: Container(
        alignment: Alignment.centerRight,
        color: cs.error,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white, size: 18),
      ),
      child: InkWell(
        onTap: () => onJumpToPage(bookmark.pageIndex),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: isActive ? cs.primaryContainer.withOpacity(0.2) : null,
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: bookmark.color != null
                      ? Color(int.tryParse(bookmark.color!) ?? 0xFF2196F3)
                      : cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bookmark.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: isActive ? cs.primary : cs.onSurface,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              Text(
                'p.${bookmark.pageIndex + 1}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
