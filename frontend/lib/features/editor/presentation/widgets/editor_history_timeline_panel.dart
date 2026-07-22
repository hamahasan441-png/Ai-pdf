import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_history_timeline_controller.dart';

/// Panel showing the full annotation edit history as a visual timeline
/// (Phase 49).
///
/// Past entries are solid, future entries are faded, the current position is
/// highlighted. Tap any entry to jump to that state (time-travel undo).
class EditorHistoryTimelinePanel extends StatelessWidget {
  final EditorHistoryTimelineState timelineState;
  final ValueChanged<int> onGoTo;
  final VoidCallback onStepBack;
  final VoidCallback onStepForward;
  final VoidCallback onClose;

  const EditorHistoryTimelinePanel({
    super.key,
    required this.timelineState,
    required this.onGoTo,
    required this.onStepBack,
    required this.onStepForward,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(12),
        bottomLeft: Radius.circular(12),
      ),
      color: cs.surface,
      child: SizedBox(
        width: 260,
        child: Column(
          children: [
            _header(cs),
            const Divider(height: 1),
            Expanded(
              child: timelineState.hasHistory
                  ? ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: timelineState.entries.length,
                      itemBuilder: (_, i) {
                        final reverseI =
                            timelineState.entries.length - 1 - i;
                        return _entryRow(reverseI, cs);
                      },
                    )
                  : Center(
                      child: Text('No edits yet',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ),
            ),
            _controls(cs),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.history, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text('Edit History',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: cs.onSurface)),
          const Spacer(),
          Text(
            '${timelineState.undoableCount}/${timelineState.totalEntries}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
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

  Widget _entryRow(int index, ColorScheme cs) {
    final entry = timelineState.entries[index];
    final isCurrent = index == timelineState.currentIndex;
    final isFuture = index > timelineState.currentIndex;

    return InkWell(
      onTap: () => onGoTo(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: isCurrent ? cs.primaryContainer.withOpacity(0.3) : null,
        child: Row(
          children: [
            // Timeline dot and line
            Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCurrent
                        ? cs.primary
                        : isFuture
                            ? cs.onSurfaceVariant.withOpacity(0.3)
                            : cs.primary.withOpacity(0.6),
                    border: isCurrent
                        ? Border.all(color: cs.primary, width: 2)
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Icon(
              _kindIcon(entry.kind),
              size: 16,
              color: isFuture ? cs.onSurfaceVariant.withOpacity(0.4) : cs.onSurface,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isFuture
                          ? cs.onSurfaceVariant.withOpacity(0.5)
                          : cs.onSurface,
                      fontWeight:
                          isCurrent ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  Text(
                    'p.${entry.pageIndex + 1} \u2022 ${_fmtTime(entry.timestamp)}',
                    style: TextStyle(
                        fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.undo, size: 20),
            onPressed:
                timelineState.currentIndex > 0 ? onStepBack : null,
            tooltip: 'Undo',
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: const Icon(Icons.redo, size: 20),
            onPressed: timelineState.currentIndex <
                    timelineState.entries.length - 1
                ? onStepForward
                : null,
            tooltip: 'Redo',
          ),
        ],
      ),
    );
  }

  IconData _kindIcon(HistoryEntryKind kind) {
    switch (kind) {
      case HistoryEntryKind.add:
        return Icons.add_circle_outline;
      case HistoryEntryKind.delete:
        return Icons.remove_circle_outline;
      case HistoryEntryKind.move:
        return Icons.open_with;
      case HistoryEntryKind.resize:
        return Icons.aspect_ratio;
      case HistoryEntryKind.style:
        return Icons.palette;
      case HistoryEntryKind.text:
        return Icons.text_fields;
      case HistoryEntryKind.batch:
        return Icons.dynamic_feed;
      case HistoryEntryKind.reorder:
        return Icons.swap_vert;
    }
  }

  String _fmtTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
}
