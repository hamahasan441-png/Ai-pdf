import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_outline_controller.dart';
import 'package:ai_pdf/features/editor/domain/services/document_outline_service.dart';

/// A collapsible sidebar panel showing the document outline (Phase 29).
///
/// Each row indents by [OutlineRow.depth], has a collapse chevron (when
/// children exist), and highlights the section the current page belongs to.
/// Tapping jumps to the target page.
class EditorOutlinePanel extends StatelessWidget {
  final EditorOutlineState outlineState;
  final ValueChanged<int> onJumpToPage;
  final ValueChanged<OutlineNode> onToggleNode;
  final VoidCallback onExpandAll;
  final VoidCallback onCollapseAll;
  final VoidCallback onClose;

  const EditorOutlinePanel({
    super.key,
    required this.outlineState,
    required this.onJumpToPage,
    required this.onToggleNode,
    required this.onExpandAll,
    required this.onCollapseAll,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = outlineState.rows;
    final activeNode = outlineState.activeSection;

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(12),
        bottomRight: Radius.circular(12),
      ),
      color: cs.surface,
      child: SizedBox(
        width: 260,
        child: Column(
          children: [
            _header(cs),
            const Divider(height: 1),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        'No outline available',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemBuilder: (_, i) => _row(rows[i], cs, activeNode),
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
          Icon(Icons.menu_book, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('Outline',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.unfold_more, size: 18),
            onPressed: onExpandAll,
            tooltip: 'Expand all',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.unfold_less, size: 18),
            onPressed: onCollapseAll,
            tooltip: 'Collapse all',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            tooltip: 'Close',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _row(OutlineRow row, ColorScheme cs, OutlineNode? activeNode) {
    final isActive = row.node == activeNode;
    return InkWell(
      onTap: () => onJumpToPage(row.node.page),
      child: Container(
        color: isActive ? cs.primaryContainer.withOpacity(0.3) : null,
        padding: EdgeInsets.only(
          left: 12.0 + row.depth * 16.0,
          right: 8,
          top: 6,
          bottom: 6,
        ),
        child: Row(
          children: [
            if (row.node.hasChildren)
              GestureDetector(
                onTap: () => onToggleNode(row.node),
                child: Icon(
                  row.node.expanded
                      ? Icons.expand_more
                      : Icons.chevron_right,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              )
            else
              const SizedBox(width: 18),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                row.node.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      row.depth == 0 ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? cs.primary : cs.onSurface,
                ),
              ),
            ),
            Text(
              '${row.node.page + 1}',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
