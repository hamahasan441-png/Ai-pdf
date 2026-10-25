import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/core/theme/motion.dart';
import 'package:ai_pdf/features/editor/application/editor_search_controller.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_design.dart';

/// Floating search bar shown above the editor when find‑in‑document is active.
///
/// A text field with the match count, match-case and whole-word toggles and
/// previous / next. With [onReplace] and [onReplaceAll] a second row, which
/// expands smoothly, replaces the current match or every match. Calls out to
/// [EditorSearchController] via the provided callbacks.
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
    final palette = EditorPalette.of(context);
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final searchState = widget.searchState;
    final hasQuery = searchState.query.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: EditorChrome.floatShadow(palette.brightness),
      ),
      child: Material(
        color: palette.barSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: palette.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _IconToggle(
                    icon: _canReplace ? Icons.find_replace : Icons.tune,
                    tooltip: _canReplace
                        ? (l10n?.replaceToggle ?? 'Find and replace')
                        : (l10n?.searchMatchCase ?? 'Match case'),
                    active: _replacing,
                    onTap: () => setState(() => _replacing = !_replacing),
                  ),
                  Expanded(
                    child: TextField(
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => searchState.hasMatches ? widget.onNext() : null,
                      decoration: InputDecoration(
                        hintText: l10n?.shortcutFind ?? 'Find in document',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onChanged: widget.onQueryChanged,
                    ),
                  ),
                  // The count changes with a quick cross-fade, red when nothing matches.
                  AnimatedSwitcher(
                    duration: Motion.of(context, Motion.quick),
                    child: hasQuery
                        ? Container(
                            key: ValueKey(searchState.badge),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: searchState.hasMatches ? cs.primaryContainer : cs.error.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              searchState.badge,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFeatures: const [FontFeature.tabularFigures()],
                                color: searchState.hasMatches ? cs.onPrimaryContainer : cs.error,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  _iconButton(Icons.keyboard_arrow_up, l10n?.searchPrevious ?? 'Previous match',
                      searchState.hasMatches ? widget.onPrevious : null),
                  _iconButton(Icons.keyboard_arrow_down, l10n?.searchNext ?? 'Next match',
                      searchState.hasMatches ? widget.onNext : null),
                  _iconButton(Icons.close, l10n?.searchClose ?? 'Close search', widget.onClose),
                ],
              ),
              // The replace row grows open and closed instead of jumping.
              AnimatedSize(
                duration: Motion.of(context, Motion.medium),
                curve: Motion.enter,
                alignment: Alignment.topCenter,
                child: _replacing
                    ? Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(8, 2, 6, 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          // Search options: what counts as a match.
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            _TextToggle(
                              label: l10n?.searchMatchCase ?? 'Match case',
                              icon: Icons.text_fields,
                              active: searchState.options.caseSensitive,
                              onTap: () => widget.onCaseSensitiveChanged(!searchState.options.caseSensitive),
                            ),
                            _TextToggle(
                              label: l10n?.searchWholeWord ?? 'Whole word',
                              icon: Icons.space_bar,
                              active: searchState.options.wholeWord,
                              onTap: () => widget.onWholeWordChanged(!searchState.options.wholeWord),
                            ),
                          ]),
                          if (_canReplace) ...[
                            const SizedBox(height: 8),
                            _replaceRow(context, l10n, searchState),
                          ],
                        ]),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _replaceRow(BuildContext context, AppLocalizations? l10n, EditorSearchState searchState) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('replaceField'),
          controller: _replacement,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: l10n?.replaceWithHint ?? 'Replace with',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: cs.primary, width: 1.4),
            ),
          ),
          onSubmitted: searchState.hasMatches ? widget.onReplace : null,
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _actionButton(l10n?.replaceOne ?? 'Replace',
                searchState.hasMatches ? () => widget.onReplace!(_replacement.text) : null,
                tonal: true),
            const SizedBox(width: 8),
            _actionButton(l10n?.replaceAll ?? 'Replace all',
                searchState.hasMatches ? () => widget.onReplaceAll!(_replacement.text) : null),
          ],
        ),
      ],
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback? onTap) => IconButton(
        icon: Icon(icon, size: 20),
        onPressed: onTap,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      );

  Widget _actionButton(String label, VoidCallback? onTap, {bool tonal = false}) {
    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    );
    return tonal
        ? FilledButton.tonal(onPressed: onTap, style: style, child: Text(label))
        : FilledButton(onPressed: onTap, style: style, child: Text(label));
  }
}

/// A small option chip that lights up when on.
class _TextToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _TextToggle({required this.label, required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      toggled: active,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: Motion.of(context, Motion.quick),
          curve: Motion.enter,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(active ? Icons.check : icon, size: 16, color: active ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// An icon button with an animated "on" background.
class _IconToggle extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  const _IconToggle({required this.icon, required this.tooltip, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        toggled: active,
        label: tooltip,
        excludeSemantics: true,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.quick),
            curve: Motion.enter,
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? cs.primaryContainer : Colors.transparent,
            ),
            child: Icon(icon, size: 20, color: active ? cs.primary : cs.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}
