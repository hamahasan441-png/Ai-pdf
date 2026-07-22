import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_shortcuts_controller.dart';

/// Dialog displaying all keyboard shortcuts, filterable by category, with
/// the ability to reassign keys (Phase 46).
class EditorShortcutsDialog extends StatelessWidget {
  final EditorShortcutsState shortcutsState;
  final ValueChanged<String?> onFilterChanged;
  final ValueChanged<String> onBeginEdit;
  final ValueChanged<String> onResetBinding;
  final VoidCallback onResetAll;
  final VoidCallback onClose;

  const EditorShortcutsDialog({
    super.key,
    required this.shortcutsState,
    required this.onFilterChanged,
    required this.onBeginEdit,
    required this.onResetBinding,
    required this.onResetAll,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = shortcutsState.filtered;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(cs),
              const SizedBox(height: 12),
              _categoryFilter(cs),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _row(items[i], cs),
                ),
              ),
              const SizedBox(height: 12),
              _footer(cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Row(
      children: [
        Icon(Icons.keyboard, size: 22, color: cs.primary),
        const SizedBox(width: 8),
        Text('Keyboard Shortcuts',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: cs.onSurface)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: onClose,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  Widget _categoryFilter(ColorScheme cs) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip('All', shortcutsState.filterCategory == null,
              () => onFilterChanged(null), cs),
          for (final cat in shortcutsState.categories)
            _chip(cat, shortcutsState.filterCategory == cat,
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

  Widget _row(ShortcutBinding binding, ColorScheme cs) {
    final isEditing = shortcutsState.editingId == binding.id;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(binding.label,
                    style: TextStyle(fontSize: 13, color: cs.onSurface)),
                Text(binding.category,
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: isEditing
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.primary, width: 2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Press keys...',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.primary,
                            fontStyle: FontStyle.italic)),
                  )
                : InkWell(
                    onTap: binding.customizable
                        ? () => onBeginEdit(binding.id)
                        : null,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        binding.keys,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: cs.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
          ),
          if (binding.customizable)
            IconButton(
              icon: const Icon(Icons.restore, size: 16),
              onPressed: () => onResetBinding(binding.id),
              tooltip: 'Reset to default',
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            ),
        ],
      ),
    );
  }

  Widget _footer(ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(onPressed: onResetAll, child: const Text('Reset all')),
        const SizedBox(width: 8),
        FilledButton(onPressed: onClose, child: const Text('Done')),
      ],
    );
  }
}
