import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_metadata_controller.dart';

/// Dialog showing and letting users edit the PDF document metadata (Phase 38).
///
/// Editable fields: title, author, subject, keywords, creator, producer.
/// Read-only: creation date, mod date, page count, PDF version, file size.
class EditorMetadataDialog extends StatelessWidget {
  final EditorMetadataState metadataState;
  final ValueChanged<String> onTitleChanged;
  final ValueChanged<String> onAuthorChanged;
  final ValueChanged<String> onSubjectChanged;
  final ValueChanged<String> onKeywordsChanged;
  final ValueChanged<String> onCreatorChanged;
  final ValueChanged<String> onProducerChanged;
  final VoidCallback onSave;
  final VoidCallback onClose;

  const EditorMetadataDialog({
    super.key,
    required this.metadataState,
    required this.onTitleChanged,
    required this.onAuthorChanged,
    required this.onSubjectChanged,
    required this.onKeywordsChanged,
    required this.onCreatorChanged,
    required this.onProducerChanged,
    required this.onSave,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = metadataState.metadata;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 560),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(cs),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    _field('Title', meta.title, onTitleChanged),
                    _field('Author', meta.author, onAuthorChanged),
                    _field('Subject', meta.subject, onSubjectChanged),
                    _field('Keywords', meta.keywords, onKeywordsChanged),
                    _field('Creator', meta.creator, onCreatorChanged),
                    _field('Producer', meta.producer, onProducerChanged),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    _readOnly('Pages', '${meta.pageCount}'),
                    if (meta.pdfVersion != null)
                      _readOnly('PDF Version', meta.pdfVersion!),
                    _readOnly('File Size', meta.fileSizeFormatted),
                    if (meta.creationDate != null)
                      _readOnly('Created', _formatDate(meta.creationDate!)),
                    if (meta.modificationDate != null)
                      _readOnly('Modified', _formatDate(meta.modificationDate!)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _actions(cs),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(ColorScheme cs) {
    return Row(
      children: [
        Icon(Icons.info_outline, color: cs.primary, size: 22),
        const SizedBox(width: 8),
        Text('Document Properties',
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

  Widget _field(String label, String value, ValueChanged<String> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        initialValue: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _readOnly(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ),
          Expanded(
              child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _actions(ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(onPressed: onClose, child: const Text('Cancel')),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: metadataState.dirty ? onSave : null,
          child: const Text('Save'),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.'
      '${dt.month.toString().padLeft(2, '0')}.'
      '${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
