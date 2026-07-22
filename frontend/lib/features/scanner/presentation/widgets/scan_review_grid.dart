import 'package:flutter/material.dart';

import 'package:ai_pdf/features/scanner/domain/entities/scan_filter.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_page.dart';

/// Reorderable grid of captured pages for the review stage (Phase 51).
///
/// Each tile shows the processed thumbnail, a page number, and quick actions
/// (rotate, edit crop, delete). Long-press-drag reorders pages.
class ScanReviewGrid extends StatelessWidget {
  final List<ScanPage> pages;
  final ValueChanged<String> onEdit;
  final ValueChanged<String> onRotate;
  final ValueChanged<String> onDelete;
  final void Function(int oldIndex, int newIndex) onReorder;

  const ScanReviewGrid({
    super.key,
    required this.pages,
    required this.onEdit,
    required this.onRotate,
    required this.onDelete,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: pages.length,
      onReorder: onReorder,
      proxyDecorator: (child, index, animation) => Material(
        elevation: 6,
        color: Colors.transparent,
        child: child,
      ),
      itemBuilder: (context, i) {
        final page = pages[i];
        return Card(
          key: ValueKey(page.id),
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    width: 64,
                    height: 84,
                    child: page.processing
                        ? const Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : Image.memory(page.displayBytes, fit: BoxFit.cover),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Page ${i + 1}',
                          style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface)),
                      Text(page.filter.label,
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.rotate_right, size: 20),
                  onPressed: () => onRotate(page.id),
                  tooltip: 'Rotate',
                ),
                IconButton(
                  icon: const Icon(Icons.crop, size: 20),
                  onPressed: () => onEdit(page.id),
                  tooltip: 'Adjust crop',
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 20, color: cs.error),
                  onPressed: () => onDelete(page.id),
                  tooltip: 'Delete',
                ),
                ReorderableDragStartListener(
                  index: i,
                  child: Icon(Icons.drag_handle, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
