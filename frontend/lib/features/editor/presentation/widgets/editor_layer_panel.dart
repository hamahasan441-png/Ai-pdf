import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;
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
            _header(context, cs, l10n),
            const Divider(height: 1),
            Expanded(
              child: layerState.hasLayers
                  ? ListView(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      children: [for (final l in layerState.layers) _layerRow(l, cs, l10n)],
                    )
                  : Center(
                      child: Text(
                        l10n.layersEmpty,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  static String labelOf(String kind, AppLocalizations l10n) => switch (kind) {
        'text' => l10n.layerText,
        'shape' => l10n.layerShapes,
        'stroke' => l10n.layerDrawings,
        'markup' => l10n.layerHighlights,
        'image' => l10n.layerImages,
        'stamp' => l10n.layerStamps,
        'note' => l10n.layerNotes,
        'form' => l10n.layerFormFields,
        _ => kind,
      };

  Widget _header(BuildContext context, ColorScheme cs, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.layers, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text(l10n.toolLayers, style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.visibility, size: 18),
            onPressed: layerState.hasLayers ? onShowAll : null,
            tooltip: l10n.layersShowAll,
          ),
          IconButton(
            icon: const Icon(Icons.visibility_off, size: 18),
            onPressed: layerState.hasLayers ? onHideAll : null,
            tooltip: l10n.layersHideAll,
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: onClose,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          ),
        ],
      ),
    );
  }

  Widget _layerRow(AnnotationLayer layer, ColorScheme cs, AppLocalizations l10n) {
    final label = labelOf(layer.kind, l10n);
    return Padding(
      key: ValueKey(layer.id),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => onToggleVisibility(layer.id),
            tooltip: layer.visible ? l10n.layersHide(label) : l10n.layersShow(label),
            icon: Icon(
              layer.visible ? Icons.visibility : Icons.visibility_off,
              size: 20,
              color: layer.visible ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          IconButton(
            onPressed: () => onToggleLock(layer.id),
            tooltip: layer.locked ? l10n.layersUnlock(label) : l10n.layersLock(label),
            icon: Icon(
              layer.locked ? Icons.lock : Icons.lock_open,
              size: 18,
              color: layer.locked ? cs.error : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
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
              semanticsLabel: l10n.layersCount(layer.itemCount),
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
