import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/application/editor_search_controller.dart';

/// Floating search bar shown above the editor when find‑in‑document is active
/// (Phase 27).
///
/// Contains a text field, match count badge, case/whole‑word toggles, and
/// prev/next navigation arrows. With [onReplace] and [onReplaceAll] it also
/// offers a second row to replace the current match or every match. Calls out
/// to [EditorSearchController] via the provided callbacks.
class EditorSearchBar extends StatefulWidget {
  final EditorSearchState searchState;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onClose;
  final ValueChanged<bool> onCaseSensitiveChanged;
  final ValueChanged<bool> onWholeWordChanged;
  final ValueChanged<String>? onReplace;
  final ValueChanged<String>? onReplaceAll;

  const EditorSearchBar({
    super.key,
    required this.searchState,
    required this.onQueryChanged,
    required this.onNext,
    required this.onPrevious,
    required this.onClose,
    required this.onCaseSensitiveChanged,
    required this.onWholeWordChanged,
    this.onReplace,
    this.onReplaceAll,
  });

  @override
  State<EditorSearchBar> createState() => _EditorSearchBarState();
}

class _EditorSearchBarState extends State<EditorSearchBar> {
  final _replacement = TextEditingController();
  bool _replacing = false;

  @override
  void dispose() {
    _replacement.dispose();
    super.dispose();
  }

  bool get _canReplace => widget.onReplace != null && widget.onReplaceAll != null;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final searchState = widget.searchState;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (_canReplace)
                  IconButton(
                    icon: Icon(_replacing ? Icons.expand_less : Icons.find_replace, size: 20),
                    onPressed: () => setState(() => _replacing = !_replacing),
                    tooltip: l10n?.replaceToggle ?? 'Find and replace',
                    isSelected: _replacing,
                    iconSize: 20,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                Expanded(
                  child: TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: l10n?.shortcutFind ?? 'Find in document',
                      border: InputBorder.none,
                      isDense: true,
                      suffixText: searchState.badge,
                      suffixStyle: TextStyle(
                        color: searchState.hasMatches ? cs.onSurface : cs.error,
                        fontSize: 12,
                      ),
                    ),
                    onChanged: widget.onQueryChanged,
                  ),
                ),
                _toggle(
                  'Aa',
                  searchState.options.caseSensitive,
                  (v) => widget.onCaseSensitiveChanged(v),
                  cs,
                  tooltip: l10n?.searchMatchCase ?? 'Match case',
                ),
                _toggle(
                  'W',
                  searchState.options.wholeWord,
                  (v) => widget.onWholeWordChanged(v),
                  cs,
                  tooltip: l10n?.searchWholeWord ?? 'Whole word',
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                  onPressed: searchState.hasMatches ? widget.onPrevious : null,
                  tooltip: l10n?.searchPrevious ?? 'Previous match',
                  iconSize: 20,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  onPressed: searchState.hasMatches ? widget.onNext : null,
                  tooltip: l10n?.searchNext ?? 'Next match',
                  iconSize: 20,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onClose,
                  tooltip: l10n?.searchClose ?? 'Close search',
                  iconSize: 20,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            if (_canReplace && _replacing)
              Row(
                children: [
                  const SizedBox(width: 32),
                  Expanded(
                    child: TextField(
                      key: const ValueKey('replaceField'),
                      controller: _replacement,
                      decoration: InputDecoration(
                        hintText: l10n?.replaceWithHint ?? 'Replace with',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: searchState.hasMatches ? widget.onReplace : null,
                    ),
                  ),
                  TextButton(
                    onPressed: searchState.hasMatches ? () => widget.onReplace!(_replacement.text) : null,
                    child: Text(l10n?.replaceOne ?? 'Replace'),
                  ),
                  TextButton(
                    onPressed: searchState.hasMatches ? () => widget.onReplaceAll!(_replacement.text) : null,
                    child: Text(l10n?.replaceAll ?? 'Replace all'),
                  ),
                ],
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
