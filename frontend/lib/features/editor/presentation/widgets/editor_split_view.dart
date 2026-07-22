import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_split_view_controller.dart';

/// Widget that renders two page viewports side-by-side or stacked (Phase 47).
///
/// Each pane shows a page image with independent navigation controls. The
/// caller provides the page bytes and the document viewport builder.
class EditorSplitView extends StatelessWidget {
  final EditorSplitViewState splitState;
  final Map<int, Uint8List> pageCache;
  final Widget Function(int pageIndex) buildPane;
  final ValueChanged<int> onLeftPageChanged;
  final ValueChanged<int> onRightPageChanged;
  final ValueChanged<SplitViewMode> onModeChanged;
  final VoidCallback onToggleSync;

  const EditorSplitView({
    super.key,
    required this.splitState,
    required this.pageCache,
    required this.buildPane,
    required this.onLeftPageChanged,
    required this.onRightPageChanged,
    required this.onModeChanged,
    required this.onToggleSync,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!splitState.isSplit) return buildPane(splitState.leftPage);

    final isVertical = splitState.mode == SplitViewMode.stacked;

    return Column(
      children: [
        _controls(cs),
        Expanded(
          child: isVertical
              ? Column(
                  children: [
                    Expanded(child: _pane(splitState.leftPage, true, cs)),
                    const Divider(height: 2),
                    Expanded(child: _pane(splitState.rightPage, false, cs)),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: _pane(splitState.leftPage, true, cs)),
                    const VerticalDivider(width: 2),
                    Expanded(child: _pane(splitState.rightPage, false, cs)),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _controls(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: cs.surfaceContainerHighest,
      child: Row(
        children: [
          SegmentedButton<SplitViewMode>(
            segments: const [
              ButtonSegment(
                  value: SplitViewMode.sideBySide,
                  icon: Icon(Icons.view_column, size: 16)),
              ButtonSegment(
                  value: SplitViewMode.stacked,
                  icon: Icon(Icons.view_agenda, size: 16)),
            ],
            selected: {splitState.mode},
            onSelectionChanged: (s) => onModeChanged(s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                  const TextStyle(fontSize: 11)),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              splitState.syncScroll ? Icons.link : Icons.link_off,
              size: 18,
            ),
            onPressed: onToggleSync,
            tooltip: splitState.syncScroll ? 'Sync on' : 'Sync off',
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          const Spacer(),
          Text(
            'L: p.${splitState.leftPage + 1}  R: p.${splitState.rightPage + 1}',
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _pane(int pageIndex, bool isLeft, ColorScheme cs) {
    return Stack(
      children: [
        buildPane(pageIndex),
        Positioned(
          bottom: 8,
          left: 8,
          right: 8,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 18),
                onPressed: pageIndex > 0
                    ? () => isLeft
                        ? onLeftPageChanged(pageIndex - 1)
                        : onRightPageChanged(pageIndex - 1)
                    : null,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                style: IconButton.styleFrom(
                  backgroundColor: cs.surface.withOpacity(0.7),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.surface.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${pageIndex + 1}/${splitState.pageCount}',
                  style: TextStyle(fontSize: 11, color: cs.onSurface),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 18),
                onPressed: pageIndex < splitState.pageCount - 1
                    ? () => isLeft
                        ? onLeftPageChanged(pageIndex + 1)
                        : onRightPageChanged(pageIndex + 1)
                    : null,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                style: IconButton.styleFrom(
                  backgroundColor: cs.surface.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
