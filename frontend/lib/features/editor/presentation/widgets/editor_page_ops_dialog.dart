import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_page_ops_controller.dart';

/// Dialog for page-level operations: extract, split, delete, rotate, insert
/// blanks (Phase 34).
///
/// The user types a page range (validated live), chooses an operation, and
/// confirms. The caller performs the actual structural change using
/// [PageReorderService].
class EditorPageOpsDialog extends StatelessWidget {
  final EditorPageOpsState pageOpsState;
  final ValueChanged<String> onRangeChanged;
  final ValueChanged<PageOperation> onOperationChanged;
  final VoidCallback onSelectAll;
  final VoidCallback onConfirm;
  final VoidCallback onClose;

  const EditorPageOpsDialog({
    super.key,
    required this.pageOpsState,
    required this.onRangeChanged,
    required this.onOperationChanged,
    required this.onSelectAll,
    required this.onConfirm,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(cs),
              const SizedBox(height: 16),
              _rangeInput(cs),
              const SizedBox(height: 12),
              _operationChips(cs),
              const SizedBox(height: 16),
              _summary(cs),
              const SizedBox(height: 16),
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
        Icon(Icons.pages, color: cs.primary, size: 22),
        const SizedBox(width: 8),
        Text(
          'Page Operations',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: onClose,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  Widget _rangeInput(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Pages (e.g. 1-3, 5, 8-10)',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: pageOpsState.parseError,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.select_all, size: 18),
                    onPressed: onSelectAll,
                    tooltip: 'Select all',
                  ),
                ),
                onChanged: onRangeChanged,
                controller: TextEditingController.fromValue(
                  TextEditingValue(text: pageOpsState.rangeSpec),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Document has ${pageOpsState.pageCount} pages',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _operationChips(ColorScheme cs) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _chip('Extract', PageOperation.extract, Icons.file_download_outlined, cs),
        _chip('Split', PageOperation.split, Icons.call_split, cs),
        _chip('Delete', PageOperation.delete, Icons.delete_outline, cs),
        _chip('Rotate \u21B6', PageOperation.rotateLeft, Icons.rotate_left, cs),
        _chip('Rotate \u21B7', PageOperation.rotateRight, Icons.rotate_right, cs),
        _chip('Insert Blank', PageOperation.insertBlank, Icons.note_add_outlined, cs),
      ],
    );
  }

  Widget _chip(
      String label, PageOperation op, IconData icon, ColorScheme cs) {
    final selected = pageOpsState.operation == op;
    return ChoiceChip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onOperationChanged(op),
      selectedColor: cs.primaryContainer,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _summary(ColorScheme cs) {
    final count = pageOpsState.selectedCount;
    final opLabel = _opLabel(pageOpsState.operation);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            pageOpsState.isValid ? Icons.info_outline : Icons.warning_amber,
            size: 16,
            color: pageOpsState.isValid ? cs.primary : cs.error,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              pageOpsState.isValid
                  ? '$opLabel $count page${count == 1 ? '' : 's'}'
                  : 'Enter a valid page range',
              style: TextStyle(fontSize: 12, color: cs.onSurface),
            ),
          ),
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
          onPressed: pageOpsState.isValid ? onConfirm : null,
          child: Text(_opLabel(pageOpsState.operation)),
        ),
      ],
    );
  }

  String _opLabel(PageOperation op) {
    switch (op) {
      case PageOperation.extract:
        return 'Extract';
      case PageOperation.split:
        return 'Split';
      case PageOperation.delete:
        return 'Delete';
      case PageOperation.rotateLeft:
        return 'Rotate Left';
      case PageOperation.rotateRight:
        return 'Rotate Right';
      case PageOperation.insertBlank:
        return 'Insert Blank';
    }
  }
}
