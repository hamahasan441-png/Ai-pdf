import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/library/domain/entities/library_item.dart';

/// What a document's menu can do.
enum LibraryItemAction { rename, pin, move, delete }

/// A single document tile in the library list.
class LibraryItemTile extends StatelessWidget {
  final LibraryItem item;
  final bool selected;
  final bool multiSelectMode;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onFavorite;
  final ValueChanged<LibraryItemAction> onAction;

  const LibraryItemTile({
    super.key,
    required this.item,
    required this.selected,
    required this.multiSelectMode,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? cs.primaryContainer.withValues(alpha: 0.3) : null,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              if (multiSelectMode)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
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
                  color: _typeColor(item.type).withValues(alpha: 0.1),
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
                            padding: const EdgeInsetsDirectional.only(end: 4),
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
                          Text(l10n.libPageCount(item.pageCount),
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                        ],
                        if (item.tags.isNotEmpty) ...[
                          Text(' \u2022 ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
                          Text(item.tags.first, style: TextStyle(fontSize: 11, color: cs.primary)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!multiSelectMode) ...[
                IconButton(
                  icon: Icon(
                    item.isFavorite ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: item.isFavorite ? cs.error : cs.onSurfaceVariant,
                  ),
                  isSelected: item.isFavorite,
                  tooltip: item.isFavorite ? l10n.libRemoveFavorite : l10n.libFavorite,
                  onPressed: onFavorite,
                ),
                PopupMenuButton<LibraryItemAction>(
                  tooltip: l10n.libMore,
                  icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
                  onSelected: onAction,
                  itemBuilder: (_) => [
                    _menuItem(LibraryItemAction.rename, Icons.edit_outlined, l10n.libRename),
                    _menuItem(LibraryItemAction.pin, item.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                        item.isPinned ? l10n.libUnpin : l10n.libPin),
                    _menuItem(LibraryItemAction.move, Icons.drive_file_move_outlined, l10n.libMoveToFolder),
                    _menuItem(LibraryItemAction.delete, Icons.delete_outline, l10n.delete, color: cs.error),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<LibraryItemAction> _menuItem(LibraryItemAction a, IconData icon, String label, {Color? color}) =>
      PopupMenuItem(
        value: a,
        child: Row(children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: color))),
        ]),
      );

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
