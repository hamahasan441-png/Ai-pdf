import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;
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
              _title(cs, l10n),
              const SizedBox(height: 16),
              _rangeInput(cs, l10n),
              const SizedBox(height: 12),
              _operationChips(cs, l10n),
              const SizedBox(height: 16),
              _summary(cs, l10n),
              const SizedBox(height: 16),
              _actions(cs, l10n),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(ColorScheme cs, AppLocalizations l10n) {
    return Row(
      children: [
        Icon(Icons.pages, color: cs.primary, size: 22),
        const SizedBox(width: 8),
        Text(
          l10n.cPageOpsTitle,
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
          tooltip: l10n.cEditorClose,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
        ),
      ],
    );
  }

  Widget _rangeInput(ColorScheme cs, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: l10n.cPageOpsRangeLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: pageOpsState.parseError == null ? null : l10n.invalidPageRange,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.select_all, size: 18),
                    onPressed: onSelectAll,
                    tooltip: l10n.cEditorSelectAll,
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
          l10n.cPageOpsDocPages(pageOpsState.pageCount),
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _operationChips(ColorScheme cs, AppLocalizations l10n) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _chip(l10n.cPageOpsExtract, PageOperation.extract, Icons.file_download_outlined, cs),
        _chip(l10n.cPageOpsSplit, PageOperation.split, Icons.call_split, cs),
        _chip(l10n.delete, PageOperation.delete, Icons.delete_outline, cs),
        _chip('${l10n.rotate} \u21B6', PageOperation.rotateLeft, Icons.rotate_left, cs),
        _chip('${l10n.rotate} \u21B7', PageOperation.rotateRight, Icons.rotate_right, cs),
        _chip(l10n.cPageOpsInsertBlank, PageOperation.insertBlank, Icons.note_add_outlined, cs),
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

  Widget _summary(ColorScheme cs, AppLocalizations l10n) {
    final count = pageOpsState.selectedCount;
    final opLabel = _opLabel(pageOpsState.operation, l10n);
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
                  ? l10n.cPageOpsSummary(opLabel, count)
                  : l10n.cPageOpsEnterValidRange,
              style: TextStyle(fontSize: 12, color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actions(ColorScheme cs, AppLocalizations l10n) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(onPressed: onClose, child: Text(l10n.cancel)),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: pageOpsState.isValid ? onConfirm : null,
          child: Text(_opLabel(pageOpsState.operation, l10n)),
        ),
      ],
    );
  }

  String _opLabel(PageOperation op, AppLocalizations l10n) {
    switch (op) {
      case PageOperation.extract:
        return l10n.cPageOpsExtract;
      case PageOperation.split:
        return l10n.cPageOpsSplit;
      case PageOperation.delete:
        return l10n.delete;
      case PageOperation.rotateLeft:
        return l10n.cPageOpsRotateLeft;
      case PageOperation.rotateRight:
        return l10n.cPageOpsRotateRight;
      case PageOperation.insertBlank:
        return l10n.cPageOpsInsertBlank;
    }
  }
}
