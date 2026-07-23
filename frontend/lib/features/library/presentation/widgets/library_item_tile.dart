import 'package:flutter/material.dart';

import 'package:ai_pdf/features/library/domain/entities/library_item.dart';

/// A single document tile in the library list.
class LibraryItemTile extends StatelessWidget {
  final LibraryItem item;
  final bool selected;
  final bool multiSelectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavorite;
  final VoidCallback onDelete;

  const LibraryItemTile({
    super.key,
    required this.item,
    required this.selected,
    required this.multiSelectMode,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer.withOpacity(0.3) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant.withOpacity(0.5),
          ),
        ),
        child: Row(
          children: [
            if (multiSelectMode)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
            // Type icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _typeColor(item.type).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon(item.type), color: _typeColor(item.type), size: 22),
            ),
            const SizedBox(width: 12),
            // Name + metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (item.isPinned)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.push_pin, size: 12, color: cs.primary),
                        ),
                      Expanded(
                        child: Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        item.sizeFormatted,
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                      if (item.pageCount > 1) ...[
                        Text(' \u2022 ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                        Text('${item.pageCount} pages',
                            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      ],
                      if (item.tags.isNotEmpty) ...[
                        Text(' \u2022 ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                        Text(item.tags.first,
                            style: TextStyle(fontSize: 11, color: cs.primary)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Favorite button
            if (!multiSelectMode)
              IconButton(
                icon: Icon(
                  item.isFavorite ? Icons.favorite : Icons.favorite_border,
                  size: 18,
                  color: item.isFavorite ? Colors.red : cs.onSurfaceVariant,
                ),
                onPressed: onFavorite,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }

  IconData _typeIcon(LibraryItemType type) {
    switch (type) {
      case LibraryItemType.pdf:
        return Icons.picture_as_pdf;
      case LibraryItemType.image:
        return Icons.image;
      case LibraryItemType.scan:
        return Icons.document_scanner;
    }
  }

  Color _typeColor(LibraryItemType type) {
    switch (type) {
      case LibraryItemType.pdf:
        return const Color(0xFFE53935);
      case LibraryItemType.image:
        return const Color(0xFF43A047);
      case LibraryItemType.scan:
        return const Color(0xFF1E88E5);
    }
  }
}
