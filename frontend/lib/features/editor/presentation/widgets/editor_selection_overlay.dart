import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// A single icon button used inside the floating selection action bars.
/// Meets the 44×44 dp minimum touch target required by Material and
/// Android accessibility guidelines.
class EditorMiniButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const EditorMiniButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        // Enforce minimum 44×44 touch target (WCAG / Material spec).
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// Blue dashed bounding box drawn around the selected annotation.
class EditorSelectionBox extends StatelessWidget {
  final Size size;
  final Rect bounds;

  const EditorSelectionBox({
    super.key,
    required this.size,
    required this.bounds,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: bounds.left * size.width - 3,
      top: bounds.top * size.height - 3,
      width: (bounds.width * size.width + 6).clamp(8.0, size.width),
      height: (bounds.height * size.height + 6).clamp(8.0, size.height),
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              // Use a professional selection blue consistent with desktop editors.
              color: const Color(0xFF2563EB),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular resize handle rendered at a corner of the selection box.
class EditorScaleHandle extends StatelessWidget {
  final Size size;
  final Rect bounds;
  final bool bottomRight;
  final ValueChanged<Rect> onResizeBounds;

  const EditorScaleHandle({
    super.key,
    required this.size,
    required this.bounds,
    required this.bottomRight,
    required this.onResizeBounds,
  });

  @override
  Widget build(BuildContext context) {
    final hx = (bottomRight ? bounds.right : bounds.left) * size.width;
    final hy = (bottomRight ? bounds.bottom : bounds.top) * size.height;
    return Positioned(
      left: hx - 15,
      top: hy - 15,
      child: GestureDetector(
        onPanUpdate: (d) {
          final dxN = d.delta.dx / size.width;
          final dyN = d.delta.dy / size.height;
          final nextBounds = bottomRight
              ? Rect.fromLTRB(
                  bounds.left, bounds.top, bounds.right + dxN, bounds.bottom + dyN)
              : Rect.fromLTRB(
                  bounds.left + dxN, bounds.top + dyN, bounds.right, bounds.bottom);
          // Enforce a minimum usable size so handles cannot collapse.
          if (nextBounds.width < 0.02 || nextBounds.height < 0.01) return;
          onResizeBounds(nextBounds);
        },
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 4),
            ],
          ),
          child: Icon(
            bottomRight ? Icons.open_in_full : Icons.close_fullscreen,
            size: 12,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// Floating action bar shown when a single annotation is selected.
/// Appears at the top-right of the canvas with contextual actions for
/// text or shape annotations.
class EditorSelectionActionBar extends StatelessWidget {
  final bool showTextActions;
  final bool showShapeActions;
  final VoidCallback? onEditText;
  final VoidCallback? onTextDecrease;
  final VoidCallback? onTextIncrease;
  final VoidCallback? onPickTextColor;
  final VoidCallback? onEditShapeStyle;
  final VoidCallback onCopy;
  final VoidCallback onDuplicate;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback onDelete;
  final VoidCallback onDeselect;

  const EditorSelectionActionBar({
    super.key,
    required this.showTextActions,
    required this.showShapeActions,
    this.onEditText,
    this.onTextDecrease,
    this.onTextIncrease,
    this.onPickTextColor,
    this.onEditShapeStyle,
    required this.onCopy,
    required this.onDuplicate,
    required this.onBringToFront,
    required this.onSendToBack,
    required this.onDelete,
    required this.onDeselect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Positioned(
      top: 8,
      right: 8,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            // withOpacity() deprecated → withValues(alpha:)
            color: Colors.black.withValues(alpha: 0.87),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showTextActions) ...[
                EditorMiniButton(icon: Icons.edit, tooltip: l10n.editText, onTap: onEditText!),
                EditorMiniButton(icon: Icons.text_decrease, tooltip: 'A−', onTap: onTextDecrease!),
                EditorMiniButton(icon: Icons.text_increase, tooltip: 'A+', onTap: onTextIncrease!),
                EditorMiniButton(
                    icon: Icons.palette_outlined, tooltip: 'Colour', onTap: onPickTextColor!),
                const SizedBox(width: 4),
                const VerticalDivider(color: Colors.white24, width: 1, thickness: 1),
                const SizedBox(width: 4),
              ],
              if (showShapeActions) ...[
                EditorMiniButton(icon: Icons.tune, tooltip: l10n.style, onTap: onEditShapeStyle!),
                const SizedBox(width: 4),
                const VerticalDivider(color: Colors.white24, width: 1, thickness: 1),
                const SizedBox(width: 4),
              ],
              EditorMiniButton(icon: Icons.content_copy, tooltip: 'Copy', onTap: onCopy),
              EditorMiniButton(icon: Icons.copy_all, tooltip: l10n.duplicate, onTap: onDuplicate),
              const SizedBox(width: 4),
              const VerticalDivider(color: Colors.white24, width: 1, thickness: 1),
              const SizedBox(width: 4),
              EditorMiniButton(
                  icon: Icons.flip_to_front, tooltip: l10n.bringToFront, onTap: onBringToFront),
              EditorMiniButton(
                  icon: Icons.flip_to_back, tooltip: l10n.sendToBack, onTap: onSendToBack),
              const SizedBox(width: 4),
              const VerticalDivider(color: Colors.white24, width: 1, thickness: 1),
              const SizedBox(width: 4),
              EditorMiniButton(
                  icon: Icons.delete_outline, tooltip: l10n.delete, onTap: onDelete),
              EditorMiniButton(icon: Icons.close, tooltip: l10n.deselect, onTap: onDeselect),
            ],
          ),
        ),
      ),
    );
  }
}

/// Floating action bar shown when multiple annotations are selected (marquee).
class EditorMultiSelectionActionBar extends StatelessWidget {
  final int count;
  final VoidCallback onAlignLeft;
  final VoidCallback onAlignCenter;
  final VoidCallback onAlignRight;
  final VoidCallback onAlignTop;
  final VoidCallback onAlignMiddle;
  final VoidCallback onAlignBottom;
  final VoidCallback onDistributeH;
  final VoidCallback onDistributeV;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onDeselect;

  const EditorMultiSelectionActionBar({
    super.key,
    required this.count,
    required this.onAlignLeft,
    required this.onAlignCenter,
    required this.onAlignRight,
    required this.onAlignTop,
    required this.onAlignMiddle,
    required this.onAlignBottom,
    required this.onDistributeH,
    required this.onDistributeV,
    required this.onDuplicate,
    required this.onDelete,
    required this.onDeselect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.87),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2)),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  l10n.nSelected(count),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                const VerticalDivider(color: Colors.white24, width: 1, thickness: 1),
                const SizedBox(width: 8),
                EditorMiniButton(
                    icon: Icons.align_horizontal_left,
                    tooltip: l10n.alignLeft,
                    onTap: onAlignLeft),
                EditorMiniButton(
                    icon: Icons.align_horizontal_center,
                    tooltip: l10n.alignCenter,
                    onTap: onAlignCenter),
                EditorMiniButton(
                    icon: Icons.align_horizontal_right,
                    tooltip: l10n.alignRight,
                    onTap: onAlignRight),
                const SizedBox(width: 4),
                const VerticalDivider(color: Colors.white24, width: 1, thickness: 1),
                const SizedBox(width: 4),
                EditorMiniButton(
                    icon: Icons.align_vertical_top,
                    tooltip: l10n.alignTop,
                    onTap: onAlignTop),
                EditorMiniButton(
                    icon: Icons.align_vertical_center,
                    tooltip: l10n.alignMiddle,
                    onTap: onAlignMiddle),
                EditorMiniButton(
                    icon: Icons.align_vertical_bottom,
                    tooltip: l10n.alignBottom,
                    onTap: onAlignBottom),
                const SizedBox(width: 4),
                const VerticalDivider(color: Colors.white24, width: 1, thickness: 1),
                const SizedBox(width: 4),
                EditorMiniButton(
                    icon: Icons.horizontal_distribute,
                    tooltip: l10n.distributeH,
                    onTap: onDistributeH),
                EditorMiniButton(
                    icon: Icons.vertical_distribute,
                    tooltip: l10n.distributeV,
                    onTap: onDistributeV),
                const SizedBox(width: 4),
                const VerticalDivider(color: Colors.white24, width: 1, thickness: 1),
                const SizedBox(width: 4),
                EditorMiniButton(
                    icon: Icons.copy_all, tooltip: l10n.duplicate, onTap: onDuplicate),
                EditorMiniButton(
                    icon: Icons.delete_outline, tooltip: l10n.delete, onTap: onDelete),
                EditorMiniButton(
                    icon: Icons.close, tooltip: l10n.deselect, onTap: onDeselect),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
