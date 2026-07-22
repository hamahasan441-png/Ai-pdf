import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_form_orchestrator_controller.dart';

/// A floating bottom bar guiding the user through multi-page form fields
/// (Phase 36).
///
/// Shows: progress indicator, current field label + page badge, skip/fill
/// buttons, and previous/next arrows. Compact enough to sit above the toolbar.
class EditorFormOrchestratorBar extends StatelessWidget {
  final EditorFormOrchestratorState orchestratorState;
  final VoidCallback onSkip;
  final VoidCallback onFillCurrent;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onStop;

  const EditorFormOrchestratorBar({
    super.key,
    required this.orchestratorState,
    required this.onSkip,
    required this.onFillCurrent,
    required this.onPrevious,
    required this.onNext,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final field = orchestratorState.currentField;
    final progress = orchestratorState.progress;

    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 4,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                // Previous
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 20),
                  onPressed: onPrevious,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
                // Field info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        field?.label ?? 'Complete',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        orchestratorState.isComplete
                            ? 'All fields filled!'
                            : 'Page ${(field?.pageIndex ?? 0) + 1} \u2022 '
                                '${orchestratorState.filledCount}/${orchestratorState.total} filled',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                // Next
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 20),
                  onPressed: onNext,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: orchestratorState.isComplete ? null : onSkip,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Skip'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: orchestratorState.isComplete ? null : onFillCurrent,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Fill'),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: onStop,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
