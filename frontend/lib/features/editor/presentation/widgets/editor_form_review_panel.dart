import 'package:flutter/material.dart';
import 'package:ai_pdf/features/editor/application/editor_form_review_controller.dart';

/// Review panel with E3.2 validation UI: red border, focus next invalid, block Apply if invalid accepted.
class EditorFormReviewPanel extends StatefulWidget {
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
  State<EditorFormReviewPanel> createState() => _EditorFormReviewPanelState();
}

class _EditorFormReviewPanelState extends State<EditorFormReviewPanel> {
  final ScrollController _scrollCtrl = ScrollController();
  int _focusedInvalidPos = -1;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<int> _invalidIndices() {
    final list = <int>[];
    for (var i = 0; i < widget.reviewState.fields.length; i++) {
      if (!widget.reviewState.fields[i].isValid) list.add(i);
    }
    return list;
  }

  void _focusNextInvalid() {
    final invalid = _invalidIndices();
    if (invalid.isEmpty) return;
    _focusedInvalidPos = (_focusedInvalidPos + 1) % invalid.length;
    final target = invalid[_focusedInvalidPos];
    final offset = target * 90.0;
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        offset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasInvalidAccepted = widget.reviewState.fields.any((f) => f.isAccepted && !f.isValid);
    final canApply = widget.reviewState.hasAccepted && !hasInvalidAccepted;
    final invalidIndices = _invalidIndices();
    final focusedFieldIndex = invalidIndices.isEmpty || _focusedInvalidPos < 0
        ? -1
        : invalidIndices[_focusedInvalidPos % invalidIndices.length];

    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      color: cs.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(cs, hasInvalidAccepted),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              controller: _scrollCtrl,
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              itemCount: widget.reviewState.fields.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) => _fieldRow(
                widget.reviewState.fields[i],
                cs,
                isFocused: i == focusedFieldIndex,
              ),
            ),
          ),
          const Divider(height: 1),
          _footer(cs, canApply, hasInvalidAccepted),
        ],
      ),
    );
  }

  Widget _header(ColorScheme cs, bool hasInvalidAccepted) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.fact_check, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Review AI Fill (${widget.reviewState.accepted}/${widget.reviewState.total} accepted)',
              style: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurface, fontSize: 14),
            ),
          ),
          if (widget.reviewState.invalidCount > 0) ...[
            GestureDetector(
              onTap: _focusNextInvalid,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasInvalidAccepted ? cs.error : cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline, size: 12, color: hasInvalidAccepted ? cs.onError : cs.onErrorContainer),
                    const SizedBox(width: 4),
                    Text(
                      '${widget.reviewState.invalidCount} invalid • tap next',
                      style: TextStyle(fontSize: 10, color: hasInvalidAccepted ? cs.onError : cs.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: widget.onClose,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _fieldRow(ProposedFieldValue field, ColorScheme cs, {bool isFocused = false}) {
    final isInvalid = !field.isValid;
    final borderColor = isInvalid ? cs.error : field.isAccepted ? const Color(0xFF4CAF50).withOpacity(0.6) : cs.outlineVariant.withOpacity(0.5);
    final bgColor = isFocused
        ? cs.errorContainer.withOpacity(0.3)
        : field.isAccepted
            ? const Color(0x0D4CAF50)
            : field.isRejected
                ? const Color(0x0DF44336)
                : isInvalid
                    ? cs.errorContainer.withOpacity(0.15)
                    : null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: isInvalid || isFocused ? 1.2 : 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(field.label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isInvalid ? cs.error : cs.onSurfaceVariant)),
              ),
              _confidenceDot(field.confidence),
              if (isInvalid) ...[const SizedBox(width: 6), Icon(Icons.error, size: 14, color: cs.error)],
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: Text(field.proposedValue, style: TextStyle(fontSize: 14, color: isInvalid ? cs.error : cs.onSurface, fontWeight: isInvalid ? FontWeight.w600 : FontWeight.normal))),
              if (field.isPending) ...[
                IconButton(icon: const Icon(Icons.check, size: 18), color: Colors.green, tooltip: 'Accept', onPressed: () => widget.onAccept(field.fieldId), constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
                IconButton(icon: const Icon(Icons.close, size: 18), color: Colors.red, tooltip: 'Reject', onPressed: () => widget.onReject(field.fieldId), constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
              ] else
                Icon(field.isAccepted ? Icons.check_circle : Icons.cancel, size: 18, color: field.isAccepted ? (isInvalid ? cs.error : Colors.green) : Colors.red),
            ],
          ),
          if (field.validationError != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(color: cs.errorContainer.withOpacity(0.7), borderRadius: BorderRadius.circular(6), border: Border.all(color: cs.error.withOpacity(0.4))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: cs.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(field.validationError!, style: TextStyle(fontSize: 11, color: cs.onErrorContainer, fontWeight: FontWeight.w600)),
                        if (field.validationSuggestion != null) ...[
                          const SizedBox(height: 4),
                          GestureDetector(
                            onTap: () => widget.onUseSuggestion?.call(field.fieldId, field.validationSuggestion!),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: cs.primary.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lightbulb, size: 12, color: cs.primary), const SizedBox(width: 4), Text('Use \"${field.validationSuggestion}\"', style: TextStyle(fontSize: 11, color: cs.primary, fontWeight: FontWeight.w600))]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _confidenceDot(double confidence) {
    final color = confidence >= 0.8 ? Colors.green : confidence >= 0.5 ? Colors.orange : Colors.red;
    return Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
  }

  Widget _footer(ColorScheme cs, bool canApply, bool hasInvalidAccepted) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        children: [
          if (hasInvalidAccepted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: cs.errorContainer, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [Icon(Icons.block, size: 14, color: cs.onErrorContainer), const SizedBox(width: 6), Expanded(child: Text('Fix invalid fields before placing. Tap invalid badge to focus next.', style: TextStyle(fontSize: 11, color: cs.onErrorContainer)))]),
            ),
          Row(
            children: [
              OutlinedButton.icon(icon: const Icon(Icons.done_all, size: 16), label: const Text('Accept valid', style: TextStyle(fontSize: 12)), onPressed: widget.reviewState.pending > 0 ? widget.onAcceptAllValid : null),
              const SizedBox(width: 8),
              OutlinedButton.icon(icon: const Icon(Icons.remove_done, size: 16), label: const Text('Reject rest', style: TextStyle(fontSize: 12)), onPressed: widget.reviewState.pending > 0 ? widget.onRejectAllPending : null),
              const Spacer(),
              Tooltip(
                message: canApply ? 'Place accepted values' : 'Fix invalid accepted first',
                child: FilledButton.icon(icon: const Icon(Icons.check, size: 16), label: Text('Apply (${widget.reviewState.accepted})', style: const TextStyle(fontSize: 12)), onPressed: canApply ? widget.onApply : null, style: FilledButton.styleFrom(backgroundColor: canApply ? null : cs.outlineVariant)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
