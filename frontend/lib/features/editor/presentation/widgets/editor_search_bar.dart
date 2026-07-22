import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_search_controller.dart';

/// Floating search bar shown above the editor when find‑in‑document is active
/// (Phase 27).
///
/// Contains a text field, match count badge, case/whole‑word toggles, and
/// prev/next navigation arrows. Calls out to [EditorSearchController] via the
/// provided callbacks — the widget itself is stateless and testable.
class EditorSearchBar extends StatelessWidget {
  final EditorSearchState searchState;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;
  final ValueChanged<bool> onCaseSensitiveChanged;
  final ValueChanged<bool> onWholeWordChanged;

  const EditorSearchBar({
    super.key,
    required this.searchState,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    required this.onCaseSensitiveChanged,
    required this.onWholeWordChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Find in document',
                  border: InputBorder.none,
                  isDense: true,
                  suffixText: searchState.badge,
                  suffixStyle: TextStyle(
                    color: searchState.hasMatches
                        ? cs.onSurface
                        : cs.error,
                    fontSize: 12,
                  ),
                ),
                onChanged: onQueryChanged,
              ),
            ),
            _toggle(
              'Aa',
              searchState.options.caseSensitive,
              (v) => onCaseSensitiveChanged(v),
              cs,
              tooltip: 'Case sensitive',
            ),
            _toggle(
              'W',
              searchState.options.wholeWord,
              (v) => onWholeWordChanged(v),
              cs,
              tooltip: 'Whole word',
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              onPressed: searchState.hasMatches ? onPrevious : null,
              tooltip: 'Previous',
              iconSize: 20,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              onPressed: searchState.hasMatches ? onNext : null,
              tooltip: 'Next',
              iconSize: 20,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 20),
              onPressed: onClose,
              tooltip: 'Close',
              iconSize: 20,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(
    String label,
    bool active,
    ValueChanged<bool> onChanged,
    ColorScheme cs, {
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () => onChanged(!active),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : null,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: active ? cs.primary : cs.outlineVariant,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: active ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
