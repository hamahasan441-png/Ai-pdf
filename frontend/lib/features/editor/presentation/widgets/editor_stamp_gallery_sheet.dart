import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_stamp_gallery_controller.dart';

/// Bottom sheet showing the stamp gallery with categories and custom add
/// (Phase 48).
class EditorStampGallerySheet extends StatelessWidget {
  final EditorStampGalleryState galleryState;
  final ValueChanged<StampItem> onStampSelected;
  final ValueChanged<StampCategory?> onFilterChanged;
  final VoidCallback? onAddCustomText;
  final VoidCallback? onAddCustomImage;
  final ValueChanged<String>? onDelete;
  final VoidCallback onClose;

  const EditorStampGallerySheet({
    super.key,
    required this.galleryState,
    required this.onStampSelected,
    required this.onFilterChanged,
    required this.onClose,
    this.onAddCustomText,
    this.onAddCustomImage,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = galleryState.filtered;

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      color: cs.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(cs),
          _categoryChips(cs),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.6,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) => _stampCard(items[i], cs),
            ),
          ),
          _footer(cs),
        ],
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.approval, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('Stamp Gallery',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                  fontSize: 14)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _categoryChips(ColorScheme cs) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip('All', galleryState.filterCategory == null,
              () => onFilterChanged(null), cs),
          for (final cat in galleryState.categories)
            _chip(_catLabel(cat), galleryState.filterCategory == cat,
                () => onFilterChanged(cat), cs),
        ],
      ),
    );
  }

  Widget _chip(
      String label, bool selected, VoidCallback onTap, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: FilterChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
        selectedColor: cs.primaryContainer,
      ),
    );
  }

  Widget _stampCard(StampItem stamp, ColorScheme cs) {
    return InkWell(
      onTap: () => onStampSelected(stamp),
      onLongPress:
          stamp.builtIn ? null : () => onDelete?.call(stamp.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Color(stamp.color).withOpacity(0.5),
            width: stamp.style == StampStyle.filled ? 0 : 2,
          ),
          color: stamp.style == StampStyle.filled
              ? Color(stamp.color).withOpacity(0.15)
              : null,
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(4),
        child: stamp.isImage
            ? const Icon(Icons.image, size: 28)
            : Text(
                stamp.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(stamp.color),
                ),
              ),
      ),
    );
  }

  Widget _footer(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (onAddCustomText != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.text_fields, size: 14),
              label:
                  const Text('Custom text', style: TextStyle(fontSize: 11)),
              onPressed: onAddCustomText,
            ),
          if (onAddCustomImage != null) ...[
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.image, size: 14),
              label:
                  const Text('From image', style: TextStyle(fontSize: 11)),
              onPressed: onAddCustomImage,
            ),
          ],
        ],
      ),
    );
  }

  String _catLabel(StampCategory cat) {
    switch (cat) {
      case StampCategory.approval:
        return 'Approval';
      case StampCategory.status:
        return 'Status';
      case StampCategory.confidential:
        return 'Confidential';
      case StampCategory.custom:
        return 'Custom';
    }
  }
}
