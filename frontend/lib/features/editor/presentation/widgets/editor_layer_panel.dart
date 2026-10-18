import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_layer_controller.dart';

/// The Layers panel: the marks on the current page grouped by kind, each
/// with show/hide and lock. The toggles change the marks themselves, so the
/// canvas, selection and export all follow them. Right-side overlay, 260 px.
class EditorLayerPanel extends StatelessWidget {
  final EditorLayerState layerState;
  final ValueChanged<String> onToggleVisibility;
  final ValueChanged<String> onToggleLock;
  final VoidCallback onShowAll;
  final VoidCallback onHideAll;
  final VoidCallback onClose;

  const EditorLayerPanel({
    super.key,
    required this.layerState,
    required this.onToggleVisibility,
    required this.onToggleLock,
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
                  ? ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [for (final l in layerState.layers) _layerRow(l, cs)],
                    )
                  : Center(
                      child: Text(
                        'No marks on this page',
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
          Text('Layers', style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.visibility, size: 18),
            onPressed: layerState.hasLayers ? onShowAll : null,
            tooltip: 'Show all',
          ),
          IconButton(
            icon: const Icon(Icons.visibility_off, size: 18),
            onPressed: layerState.hasLayers ? onHideAll : null,
            tooltip: 'Hide all',
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onClose,
            tooltip: 'Close',
          ),
        ],
      ),
    );
  }

  Widget _layerRow(AnnotationLayer layer, ColorScheme cs) {
    return Padding(
      key: ValueKey(layer.id),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => onToggleVisibility(layer.id),
            tooltip: layer.visible ? 'Hide ${layer.label}' : 'Show ${layer.label}',
            icon: Icon(
              layer.visible ? Icons.visibility : Icons.visibility_off,
              size: 20,
              color: layer.visible ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          IconButton(
            onPressed: () => onToggleLock(layer.id),
            tooltip: layer.locked ? 'Unlock ${layer.label}' : 'Lock ${layer.label}',
            icon: Icon(
              layer.locked ? Icons.lock : Icons.lock_open,
              size: 18,
              color: layer.locked ? cs.error : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              layer.label,
              style: TextStyle(
                fontSize: 14,
                color: layer.visible ? cs.onSurface : cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${layer.itemCount}',
              semanticsLabel: '${layer.itemCount} marks',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
