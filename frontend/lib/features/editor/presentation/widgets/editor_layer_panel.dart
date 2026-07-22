import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_layer_controller.dart';

/// A panel showing the annotation layer stack for the current page (Phase 32).
///
/// Each row has: visibility toggle, lock toggle, opacity slider, item count
/// badge, and a reorder handle. The panel supports "show all / hide all"
/// bulk actions. Designed as a right-side overlay (260 px).
class EditorLayerPanel extends StatelessWidget {
  final EditorLayerState layerState;
  final ValueChanged<String> onToggleVisibility;
  final ValueChanged<String> onToggleLock;
  final void Function(String layerId, double opacity) onSetOpacity;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onShowAll;
  final VoidCallback onHideAll;
  final VoidCallback onClose;

  const EditorLayerPanel({
    super.key,
    required this.layerState,
    required this.onToggleVisibility,
    required this.onToggleLock,
    required this.onSetOpacity,
    required this.onReorder,
    required this.onShowAll,
    required this.onHideAll,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
              child: layerState.hasLayers
                  ? ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      itemCount: layerState.layers.length,
                      onReorder: onReorder,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemBuilder: (_, i) =>
                          _layerRow(layerState.layers[i], i, cs),
                    )
                  : Center(
                      child: Text(
                        'No annotations on this page',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
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
          Icon(Icons.layers, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('Layers',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.visibility, size: 16),
            onPressed: onShowAll,
            tooltip: 'Show all',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(Icons.visibility_off, size: 16),
            onPressed: onHideAll,
            tooltip: 'Hide all',
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

  Widget _layerRow(AnnotationLayer layer, int index, ColorScheme cs) {
    return Container(
      key: ValueKey(layer.id),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: Icon(Icons.drag_handle,
                    size: 18, color: cs.onSurfaceVariant),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onToggleVisibility(layer.id),
                child: Icon(
                  layer.visible ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                  color: layer.visible ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => onToggleLock(layer.id),
                child: Icon(
                  layer.locked ? Icons.lock : Icons.lock_open,
                  size: 16,
                  color: layer.locked ? cs.error : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  layer.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: layer.visible ? cs.onSurface : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${layer.itemCount}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          SizedBox(
            height: 20,
            child: Slider(
              value: layer.opacity,
              min: 0,
              max: 1,
              onChanged: (v) => onSetOpacity(layer.id, v),
            ),
          ),
        ],
      ),
    );
  }
}
