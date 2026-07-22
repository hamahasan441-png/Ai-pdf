import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_export_presets_controller.dart';

/// Bottom sheet for choosing / managing export presets and batch export
/// (Phase 41).
class EditorExportPresetsSheet extends StatelessWidget {
  final EditorExportPresetsState presetsState;
  final ValueChanged<ExportPreset> onExportWith;
  final VoidCallback? onSaveNew;
  final ValueChanged<String>? onDelete;
  final VoidCallback onClose;

  const EditorExportPresetsSheet({
    super.key,
    required this.presetsState,
    required this.onExportWith,
    required this.onClose,
    this.onSaveNew,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      color: cs.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(cs),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.all(12),
              itemCount: presetsState.presets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _presetCard(presetsState.presets[i], cs),
            ),
          ),
          if (presetsState.batchRunning) _batchProgress(cs),
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
          Icon(Icons.tune, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('Export Presets',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface, fontSize: 14)),
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

  Widget _presetCard(ExportPreset preset, ColorScheme cs) {
    return InkWell(
      onTap: () => onExportWith(preset),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(_formatIcon(preset.format), size: 24, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(preset.name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                  Text(
                    '${preset.format.name.toUpperCase()} \u2022 ${preset.quality.name} \u2022 '
                    '${preset.flattenAnnotations ? "flattened" : "layered"}',
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (!preset.builtIn && onDelete != null)
              IconButton(
                icon: Icon(Icons.delete_outline, size: 16, color: cs.error),
                onPressed: () => onDelete!(preset.id),
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
          ],
        ),
      ),
    );
  }

  Widget _batchProgress(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          LinearProgressIndicator(
            value: presetsState.batchProgress,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          Text(
            'Batch: ${presetsState.batchDone}/${presetsState.batchTotal} done'
            '${presetsState.batchFailed > 0 ? " (${presetsState.batchFailed} failed)" : ""}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _footer(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onSaveNew != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Save new', style: TextStyle(fontSize: 12)),
              onPressed: onSaveNew,
            ),
        ],
      ),
    );
  }

  IconData _formatIcon(ExportFormat f) {
    switch (f) {
      case ExportFormat.pdf:
        return Icons.picture_as_pdf;
      case ExportFormat.png:
        return Icons.image;
      case ExportFormat.jpeg:
        return Icons.photo;
      case ExportFormat.tiff:
        return Icons.burst_mode;
    }
  }
}
