import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/application/editor_compare_controller.dart';
import 'package:ai_pdf/features/editor/data/document_diff_service.dart';

/// Unified view of the document comparison (Phase 30 wiring).
///
/// Shows the diff produced by [EditorCompareController] as one scrollable
/// list: removed lines (old version) above the added lines (this document)
/// at each change, with the change statistics pinned to the top. The
/// controller also offers a side-by-side mode; it is not shown here because
/// the flat segment list of the diff service has no reliable pairing between
/// old and new lines yet — an unimplemented toggle must not ship.
class EditorCompareSheet extends StatelessWidget {
  final EditorCompareState state;

  const EditorCompareSheet({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.compareTitle,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _chip(context, l10n.compareAdded, state.stats.added, Colors.green),
                    const SizedBox(width: 8),
                    _chip(context, l10n.compareRemoved, state.stats.removed, Colors.red),
                    const SizedBox(width: 8),
                    _chip(context, l10n.compareUnchanged, state.stats.unchanged, cs.outline),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              const Divider(height: 1),
              Expanded(
                child: _DiffList(state: state, controller: controller),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(BuildContext context, String label, int count, Color color) {
    return Chip(
      avatar: Icon(Icons.circle, size: 10, color: color),
      label: Text('$label: $count'),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _DiffList extends StatelessWidget {
  final EditorCompareState state;

  const _DiffList({required this.state, this.controller});

  /// The sheet's scroll controller, so dragging the list drags the sheet.
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    if (!state.lineSegments.any((s) => s.kind != DiffKind.unchanged)) {
      return Center(child: Text(AppLocalizations.of(context)!.compareIdentical));
    }
    final rows = _buildRows(context, state.lineSegments);
    return ListView.builder(
      controller: controller,
      itemCount: rows.length,
      itemBuilder: (context, index) => rows[index],
    );
  }

  /// Removed lines first, then the additions that replace them, with long
  /// runs of unchanged context collapsed to two lines each side.
  List<Widget> _buildRows(BuildContext context, List<DiffSegment> segments) {
    const contextShown = 2;
    final removedStyle = TextStyle(
      color: Colors.red.shade700,
      decoration: TextDecoration.lineThrough,
      decorationColor: Colors.red.shade700,
    );
    final addedStyle = TextStyle(color: Colors.green.shade700);
    final unchangedStyle = Theme.of(context).textTheme.bodyMedium!;

    final rows = <Widget>[];
    var i = 0;
    while (i < segments.length) {
      final removed = <String>[];
      while (i < segments.length && segments[i].kind == DiffKind.removed) {
        removed.add(segments[i].text);
        i++;
      }
      final added = <String>[];
      while (i < segments.length && segments[i].kind == DiffKind.added) {
        added.add(segments[i].text);
        i++;
      }
      for (final r in removed) {
        rows.add(_Line(text: r, style: removedStyle, icon: Icons.remove));
      }
      for (final a in added) {
        rows.add(_Line(text: a, style: addedStyle, icon: Icons.add));
      }
      var unchanged = 0;
      while (i < segments.length && segments[i].kind == DiffKind.unchanged) {
        unchanged++;
        i++;
      }
      if (unchanged > 0) {
        final runStart = i - unchanged;
        // A short run is shown whole; a long one keeps [contextShown] lines
        // at each end around a "… n more" note.
        final collapse = unchanged > contextShown * 2;
        final head = collapse ? contextShown : unchanged;
        final tail = collapse ? contextShown : 0;
        for (var k = 0; k < head; k++) {
          rows.add(_Line(text: segments[runStart + k].text, style: unchangedStyle));
        }
        if (collapse) {
          rows.add(Padding(
            padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 16),
            child: Text(
              AppLocalizations.of(context)!.compareEllipsised(unchanged - contextShown * 2),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ));
        }
        for (var k = 0; k < tail; k++) {
          rows.add(_Line(text: segments[i - tail + k].text, style: unchangedStyle));
        }
      }
    }
    return rows;
  }
}

class _Line extends StatelessWidget {
  final String text;
  final TextStyle style;
  final IconData? icon;

  const _Line({required this.text, required this.style, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: icon == null
                ? null
                : Icon(icon, size: 14, color: style.color),
          ),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
