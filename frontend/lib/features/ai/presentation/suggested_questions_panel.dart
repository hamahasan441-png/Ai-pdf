import 'package:flutter/material.dart';

/// Suggested Questions + Action Items Panel — E2.6 Enhancement-Based Masterplan.
///
/// After /analyze returns {suggested_questions[], action_items[]}, render actionable checklists
/// with page jump. Action items → local tasks opt-in via notification_service.dart

class SuggestedQuestionsPanel extends StatelessWidget {
  final List<String> suggestedQuestions;
  final List<String> actionItems;
  final void Function(String question) onQuestionTap;
  final void Function(String action)? onActionTap;
  final VoidCallback? onClose;

  const SuggestedQuestionsPanel({
    super.key,
    required this.suggestedQuestions,
    required this.actionItems,
    required this.onQuestionTap,
    this.onActionTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (suggestedQuestions.isEmpty && actionItems.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 18, color: cs.primary),
                const SizedBox(width: 6),
                Text('Suggested', style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface)),
                const Spacer(),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: onClose,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  ),
              ],
            ),
            if (suggestedQuestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Ask about this document:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: suggestedQuestions.map((q) => ActionChip(
                  avatar: const Icon(Icons.help_outline, size: 14),
                  label: Text(q, style: const TextStyle(fontSize: 12)),
                  onPressed: () => onQuestionTap(q),
                )).toList(),
              ),
            ],
            if (actionItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Action items:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              const SizedBox(height: 6),
              for (final action in actionItems)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Checkbox(
                        value: false,
                        onChanged: (_) => onActionTap?.call(action),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => onActionTap?.call(action),
                          child: Text(action, style: const TextStyle(fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
