import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_autosave_controller.dart';

/// Dialog shown on app start when unsaved sessions are found (Phase 39).
///
/// Lists each recovery entry with file name, date, and page/annotation counts.
/// User can restore one or discard all.
class EditorRecoveryDialog extends StatelessWidget {
  final List<RecoveryEntry> entries;
  final ValueChanged<String> onRestore;
  final VoidCallback onDiscardAll;

  const EditorRecoveryDialog({
    super.key,
    required this.entries,
    required this.onRestore,
    required this.onDiscardAll,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 420),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.restore, color: cs.primary, size: 24),
                  const SizedBox(width: 8),
                  Text('Recover unsaved work',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      )),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'The app closed unexpectedly. Would you like to restore your work?',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _entryCard(entries[i], cs),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: onDiscardAll,
                    child: Text('Discard all',
                        style: TextStyle(color: cs.error)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _entryCard(RecoveryEntry entry, ColorScheme cs) {
    return InkWell(
      onTap: () => onRestore(entry.id),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.description, size: 28, color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.fileName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${entry.pageCount} pages \u2022 ${entry.annotationCount} annotations',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  Text(
                    _formatDate(entry.savedAt),
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.'
      '${dt.month.toString().padLeft(2, '0')}.'
      '${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
