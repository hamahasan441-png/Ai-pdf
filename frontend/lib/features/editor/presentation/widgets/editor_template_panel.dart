import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_template_controller.dart';

/// Panel displaying the annotation template/preset library (Phase 35).
///
/// Shows categories as filter chips, a grid of template cards (icon + name),
/// tap to apply, long-press to rename/delete. A "Save current" button at the
/// bottom lets users save the selected annotation as a new template.
class EditorTemplatePanel extends StatelessWidget {
  final EditorTemplateState templateState;
  final ValueChanged<AnnotationTemplate> onApply;
  final ValueChanged<String>? onDelete;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<TemplateKind?> onKindChanged;
  final VoidCallback? onSaveCurrent;
  final VoidCallback onClose;

  const EditorTemplatePanel({
    super.key,
    required this.templateState,
    required this.onApply,
    required this.onCategoryChanged,
    required this.onKindChanged,
    required this.onClose,
    this.onDelete,
    this.onSaveCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = templateState.filtered;

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
            _categoryChips(cs),
            const Divider(height: 1),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Text('No templates',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(8),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.4,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _card(items[i], cs),
                    ),
            ),
            if (onSaveCurrent != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(8),
                child: FilledButton.icon(
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save current as template',
                      style: TextStyle(fontSize: 12)),
                  onPressed: onSaveCurrent,
                ),
              ),
            ],
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
          Icon(Icons.dashboard_customize, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('Templates',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
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
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _chip('All', templateState.selectedCategory == null, () => onCategoryChanged(null), cs),
          for (final cat in templateState.categories)
            _chip(cat, templateState.selectedCategory == cat, () => onCategoryChanged(cat), cs),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap, ColorScheme cs) {
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

  Widget _card(AnnotationTemplate template, ColorScheme cs) {
    return InkWell(
      onTap: () => onApply(template),
      onLongPress: template.builtIn ? null : () => onDelete?.call(template.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(_iconFor(template.kind), size: 28, color: cs.primary),
            const SizedBox(height: 4),
            Text(
              template.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: cs.onSurface),
              textAlign: TextAlign.center,
            ),
            Text(
              template.category,
              style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(TemplateKind kind) {
    switch (kind) {
      case TemplateKind.text:
        return Icons.text_fields;
      case TemplateKind.stamp:
        return Icons.approval;
      case TemplateKind.shape:
        return Icons.crop_square;
      case TemplateKind.image:
        return Icons.image;
      case TemplateKind.composite:
        return Icons.widgets;
    }
  }
}
