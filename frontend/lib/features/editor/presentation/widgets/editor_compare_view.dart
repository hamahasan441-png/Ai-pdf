import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_compare_controller.dart';
import 'package:ai_pdf/features/editor/data/document_diff_service.dart';

/// Full‑screen compare view showing a line‑level diff of two documents
/// (Phase 30).
///
/// Supports unified mode (single scrollable list, color‑coded) and
/// side‑by‑side mode (two columns, scroll‑locked). A stats bar at the top
/// summarises added/removed/unchanged counts. The caller provides
/// [EditorCompareState] and callbacks — the widget is stateless.
class EditorCompareView extends StatelessWidget {
  final EditorCompareState compareState;
  final VoidCallback onClose;
  final ValueChanged<CompareMode> onModeChanged;

  const EditorCompareView({
    super.key,
    required this.compareState,
    required this.onClose,
    required this.onModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare Documents'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onClose,
        ),
        actions: [
          ToggleButtons(
            borderRadius: BorderRadius.circular(8),
            isSelected: [
              compareState.mode == CompareMode.unified,
              compareState.mode == CompareMode.sideBySide,
            ],
            onPressed: (i) => onModeChanged(
                i == 0 ? CompareMode.unified : CompareMode.sideBySide),
            children: const [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('Unified', style: TextStyle(fontSize: 12)),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('Side‑by‑Side', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          _statsBar(cs),
          const Divider(height: 1),
          Expanded(
            child: compareState.mode == CompareMode.unified
                ? _unifiedView(cs)
                : _sideBySideView(cs),
          ),
        ],
      ),
    );
  }

  Widget _statsBar(ColorScheme cs) {
    final s = compareState.stats;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: cs.surfaceContainerHighest,
      child: Row(
        children: [
          if (compareState.oldLabel != null)
            Text('${compareState.oldLabel} → ${compareState.newLabel ?? "new"}',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const Spacer(),
          _badge('+${s.added}', const Color(0xFF4CAF50)),
          const SizedBox(width: 8),
          _badge('-${s.removed}', const Color(0xFFF44336)),
          const SizedBox(width: 8),
          _badge('=${s.unchanged}', Colors.grey),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _unifiedView(ColorScheme cs) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: compareState.lineSegments.length,
      itemBuilder: (_, i) {
        final seg = compareState.lineSegments[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          margin: const EdgeInsets.only(bottom: 1),
          decoration: BoxDecoration(
            color: _bgColor(seg.kind),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                child: Text(
                  _prefix(seg.kind),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: _fgColor(seg.kind),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  seg.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: seg.kind == DiffKind.unchanged
                        ? cs.onSurface
                        : _fgColor(seg.kind),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sideBySideView(ColorScheme cs) {
    final oldLines = <DiffSegment>[];
    final newLines = <DiffSegment>[];
    for (final seg in compareState.lineSegments) {
      if (seg.kind == DiffKind.unchanged) {
        oldLines.add(seg);
        newLines.add(seg);
      } else if (seg.kind == DiffKind.removed) {
        oldLines.add(seg);
        newLines.add(const DiffSegment(DiffKind.unchanged, ''));
      } else {
        oldLines.add(const DiffSegment(DiffKind.unchanged, ''));
        newLines.add(seg);
      }
    }
    final controller = ScrollController();
    return Row(
      children: [
        Expanded(child: _column(oldLines, cs, compareState.oldLabel ?? 'Old', controller)),
        const VerticalDivider(width: 1),
        Expanded(child: _column(newLines, cs, compareState.newLabel ?? 'New', controller)),
      ],
    );
  }

  Widget _column(
    List<DiffSegment> lines,
    ColorScheme cs,
    String label,
    ScrollController controller,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          color: cs.surfaceContainerHighest,
          alignment: Alignment.centerLeft,
          child: Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurfaceVariant)),
        ),
        Expanded(
          child: ListView.builder(
            controller: controller,
            padding: const EdgeInsets.all(8),
            itemCount: lines.length,
            itemBuilder: (_, i) {
              final seg = lines[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(bottom: 1),
                decoration: BoxDecoration(
                  color: _bgColor(seg.kind),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  seg.text.isEmpty ? ' ' : seg.text,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color:
                        seg.kind == DiffKind.unchanged ? cs.onSurface : _fgColor(seg.kind),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Color? _bgColor(DiffKind kind) {
    switch (kind) {
      case DiffKind.added:
        return const Color(0x1A4CAF50);
      case DiffKind.removed:
        return const Color(0x1AF44336);
      case DiffKind.unchanged:
        return null;
    }
  }

  Color _fgColor(DiffKind kind) {
    switch (kind) {
      case DiffKind.added:
        return const Color(0xFF2E7D32);
      case DiffKind.removed:
        return const Color(0xFFC62828);
      case DiffKind.unchanged:
        return Colors.black;
    }
  }

  String _prefix(DiffKind kind) {
    switch (kind) {
      case DiffKind.added:
        return '+';
      case DiffKind.removed:
        return '-';
      case DiffKind.unchanged:
        return ' ';
    }
  }
}
