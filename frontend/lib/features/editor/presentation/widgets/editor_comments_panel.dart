import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_comments_controller.dart';

/// Panel showing annotation review comments (Phase 40).
///
/// Lists comments with author, text, date, and resolve status. Supports
/// adding new comments, resolving, editing, and filtering resolved/open.
class EditorCommentsPanel extends StatelessWidget {
  final EditorCommentsState commentsState;
  final VoidCallback onClose;
  final VoidCallback onToggleResolved;
  final ValueChanged<String> onResolve;
  final ValueChanged<String> onUnresolve;
  final ValueChanged<String> onDelete;
  final void Function(int page, String annotationId)? onJumpTo;
  final VoidCallback? onExport;

  const EditorCommentsPanel({
    super.key,
    required this.commentsState,
    required this.onClose,
    required this.onToggleResolved,
    required this.onResolve,
    required this.onUnresolve,
    required this.onDelete,
    this.onJumpTo,
    this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = commentsState.visibleComments;

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(12),
        bottomLeft: Radius.circular(12),
      ),
      color: cs.surface,
      child: SizedBox(
        width: 280,
        child: Column(
          children: [
            _header(cs),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'No comments yet',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) => _commentRow(items[i], cs),
                    ),
            ),
            _footer(cs),
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
          Icon(Icons.comment, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Comments (${commentsState.unresolvedCount} open)',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
          ),
          IconButton(
            icon: Icon(
              commentsState.showResolved
                  ? Icons.visibility
                  : Icons.visibility_off,
              size: 16,
            ),
            onPressed: onToggleResolved,
            tooltip: commentsState.showResolved
                ? 'Hide resolved'
                : 'Show resolved',
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

  Widget _commentRow(AnnotationComment comment, ColorScheme cs) {
    return InkWell(
      onTap: () => onJumpTo?.call(comment.pageIndex, comment.annotationId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 12,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    comment.author.isNotEmpty ? comment.author[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 11, color: cs.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    comment.author,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface),
                  ),
                ),
                Text(
                  'p.${comment.pageIndex + 1}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              comment.text,
              style: TextStyle(
                fontSize: 12,
                color: comment.resolved
                    ? cs.onSurfaceVariant
                    : cs.onSurface,
                decoration: comment.resolved
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                if (!comment.resolved)
                  _miniButton('Resolve', Icons.check, () => onResolve(comment.id), cs)
                else
                  _miniButton('Reopen', Icons.undo, () => onUnresolve(comment.id), cs),
                const SizedBox(width: 4),
                _miniButton('Delete', Icons.delete_outline, () => onDelete(comment.id), cs),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniButton(
      String label, IconData icon, VoidCallback onTap, ColorScheme cs) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: cs.onSurfaceVariant),
            const SizedBox(width: 2),
            Text(label,
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _footer(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Text(
            '${commentsState.totalCount} total \u2022 '
            '${commentsState.resolvedCount} resolved',
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
          const Spacer(),
          if (onExport != null)
            TextButton.icon(
              icon: const Icon(Icons.download, size: 14),
              label: const Text('Export', style: TextStyle(fontSize: 11)),
              onPressed: onExport,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 28),
              ),
            ),
        ],
      ),
    );
  }
}
