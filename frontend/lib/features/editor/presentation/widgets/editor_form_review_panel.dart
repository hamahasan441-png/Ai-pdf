import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_form_review_controller.dart';

/// Bottom sheet / panel showing AI-proposed field values for review (Phase 33).
///
/// Each field row shows: label, proposed value, validation badge (green check
/// or red X with error text + suggestion), confidence indicator, and
/// accept/reject buttons. Bulk actions: "Accept all valid", "Reject remaining",
/// "Apply accepted".
class EditorFormReviewPanel extends StatelessWidget {
  final EditorFormReviewState reviewState;
  final ValueChanged<String> onAccept;
  final ValueChanged<String> onReject;
  final VoidCallback onAcceptAllValid;
  final VoidCallback onRejectAllPending;
  final VoidCallback onApply;
  final VoidCallback onClose;
  final void Function(String fieldId, String value)? onEditValue;
  final void Function(String fieldId, String suggestion)? onUseSuggestion;

  const EditorFormReviewPanel({
    super.key,
    required this.reviewState,
    required this.onAccept,
    required this.onReject,
    required this.onAcceptAllValid,
    required this.onRejectAllPending,
    required this.onApply,
    required this.onClose,
    this.onEditValue,
    this.onUseSuggestion,
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
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemCount: reviewState.fields.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _fieldRow(reviewState.fields[i], cs),
            ),
          ),
          const Divider(height: 1),
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
          Icon(Icons.fact_check, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Review AI Fill (${reviewState.accepted}/${reviewState.total} accepted)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
                fontSize: 14,
              ),
            ),
          ),
          if (reviewState.invalidCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${reviewState.invalidCount} invalid',
                style: TextStyle(fontSize: 10, color: cs.onErrorContainer),
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClose,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(ProposedFieldValue field, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: field.isAccepted
            ? const Color(0x0D4CAF50)
            : field.isRejected
                ? const Color(0x0DF44336)
                : null,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  field.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              _confidenceDot(field.confidence, cs),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  field.proposedValue,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                ),
              ),
              if (field.isPending) ...[
                IconButton(
                  icon: const Icon(Icons.check, size: 18),
                  color: Colors.green,
                  onPressed: () => onAccept(field.fieldId),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.red,
                  onPressed: () => onReject(field.fieldId),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ] else
                Icon(
                  field.isAccepted ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: field.isAccepted ? Colors.green : Colors.red,
                ),
            ],
          ),
          if (field.validationError != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.warning_amber, size: 14, color: cs.error),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    field.validationError!,
                    style: TextStyle(fontSize: 11, color: cs.error),
                  ),
                ),
                if (field.validationSuggestion != null)
                  TextButton(
                    onPressed: () => onUseSuggestion?.call(
                        field.fieldId, field.validationSuggestion!),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 24),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                    child: Text('Use "${field.validationSuggestion}"'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _confidenceDot(double confidence, ColorScheme cs) {
    final color = confidence >= 0.8
        ? Colors.green
        : confidence >= 0.5
            ? Colors.orange
            : Colors.red;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }

  Widget _footer(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.done_all, size: 16),
            label: const Text('Accept valid', style: TextStyle(fontSize: 12)),
            onPressed: reviewState.pending > 0 ? onAcceptAllValid : null,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.remove_done, size: 16),
            label: const Text('Reject rest', style: TextStyle(fontSize: 12)),
            onPressed: reviewState.pending > 0 ? onRejectAllPending : null,
          ),
          const Spacer(),
          FilledButton.icon(
            icon: const Icon(Icons.check, size: 16),
            label: Text('Apply (${reviewState.accepted})',
                style: const TextStyle(fontSize: 12)),
            onPressed: reviewState.hasAccepted ? onApply : null,
          ),
        ],
      ),
    );
  }
}
