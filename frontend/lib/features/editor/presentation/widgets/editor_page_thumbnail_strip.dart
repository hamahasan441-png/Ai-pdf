import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A horizontally scrollable strip of page thumbnails for quick navigation
/// and page management (tap to jump, long-press for delete/duplicate).
///
/// Sits above the main toolbar. Each thumbnail shows a scaled-down version of
/// the rendered page (from the cache), with the current page highlighted.
class EditorPageThumbnailStrip extends StatelessWidget {
  final int pageCount;
  final int currentPage;
  final Map<int, Uint8List> pageCache;
  final ValueChanged<int> onPageTap;
  final void Function(int index, String action)? onPageAction;

  const EditorPageThumbnailStrip({
    super.key,
    required this.pageCount,
    required this.currentPage,
    required this.pageCache,
    required this.onPageTap,
    this.onPageAction,
  });

  @override
  Widget build(BuildContext context) {
    if (pageCount <= 1) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 72,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        itemCount: pageCount,
        itemBuilder: (context, index) {
          final isCurrent = index == currentPage;
          final bytes = pageCache[index];
          return GestureDetector(
            onTap: () => onPageTap(index),
            onLongPress: onPageAction == null
                ? null
                : () => _showActions(context, index),
            child: Container(
              width: 44,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                border: Border.all(
                  color: isCurrent ? cs.primary : cs.outlineVariant,
                  width: isCurrent ? 2.5 : 1,
                ),
                borderRadius: BorderRadius.circular(4),
                color: cs.surface,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: bytes != null
                    ? Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : Center(
                        child: Text(
                          '${index + 1}',
                          style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showActions(BuildContext context, int index) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Duplicate page'),
              onTap: () {
                Navigator.pop(ctx);
                onPageAction?.call(index, 'duplicate');
              },
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Insert blank page after'),
              onTap: () {
                Navigator.pop(ctx);
                onPageAction?.call(index, 'insert');
              },
            ),
            if (pageCount > 1)
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red.shade700),
                title: Text('Delete page', style: TextStyle(color: Colors.red.shade700)),
                onTap: () {
                  Navigator.pop(ctx);
                  onPageAction?.call(index, 'delete');
                },
              ),
          ],
        ),
      ),
    );
  }
}
