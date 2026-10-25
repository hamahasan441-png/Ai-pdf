import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/domain/services/rotation_math.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_design.dart';

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
    final palette = EditorPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(10),
        // The tap target is the full 44×44 box; the icon stays visually
        // compact so the bars keep their density.
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Icon(icon, size: 20, color: palette.barForeground),
          ),
        ),
      ),
    );
  }
}

/// A quiet bounding box drawn around the selected annotation *only while
/// the user is in the explicit Move/Resize (transform) mode*. Plain
/// selection is communicated with a light tint, never a border.
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
    final palette = EditorPalette.of(context);
    return Positioned(
      left: bounds.left * size.width - 2,
      top: bounds.top * size.height - 2,
      width: (bounds.width * size.width + 4).clamp(8.0, size.width),
      height: (bounds.height * size.height + 4).clamp(8.0, size.height),
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: palette.selectionBorder,
              width: 1.2,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }
}

/// A circular resize handle rendered at a corner of the selection box.
/// Compact (26 dp visual inside a 48 dp touch target) and shown only in
/// transform mode, so the page is never dotted with handles by accident.
class EditorScaleHandle extends StatelessWidget {
  final Size size;
  final Rect bounds;
  final bool bottomRight;
  final ValueChanged<Rect> onResizeBounds;

  /// Fired when the resize drag begins / ends, so the history engine can record
  /// the whole resize as a single undoable step.
  final VoidCallback? onResizeStart;
  final VoidCallback? onResizeEnd;

  const EditorScaleHandle({
    super.key,
    required this.size,
    required this.bounds,
    required this.bottomRight,
    required this.onResizeBounds,
    this.onResizeStart,
    this.onResizeEnd,
  });

  @override
  Widget build(BuildContext context) {
    final palette = EditorPalette.of(context);
    final hx = (bottomRight ? bounds.right : bounds.left) * size.width;
    final hy = (bottomRight ? bounds.bottom : bounds.top) * size.height;
    return Positioned(
      left: hx - 24,
      top: hy - 24,
      width: 48,
      height: 48,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: onResizeStart == null ? null : (_) => onResizeStart!(),
        onPanEnd: onResizeEnd == null ? null : (_) => onResizeEnd!(),
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
        child: Center(
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: palette.handleColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Color(0x42000000), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A circular rotation handle rendered above the selection box. Dragging it
/// turns the object around its centre. Shown only for object types that render
/// and export rotation end-to-end (images and stamps), and only while the
/// user is in transform mode.
class EditorRotateHandle extends StatelessWidget {
  final Size size;
  final Rect bounds;
  final ValueChanged<double> onRotate;
  final VoidCallback? onRotateStart;
  final VoidCallback? onRotateEnd;

  const EditorRotateHandle({
    super.key,
    required this.size,
    required this.bounds,
    required this.onRotate,
    this.onRotateStart,
    this.onRotateEnd,
  });

  @override
  Widget build(BuildContext context) {
    final palette = EditorPalette.of(context);
    final left = bounds.center.dx * size.width - 24;
    final top = bounds.top * size.height - 56;
    final center = Offset(
      bounds.center.dx * size.width,
      bounds.center.dy * size.height,
    );
    return Positioned(
      left: left,
      top: top,
      width: 48,
      height: 48,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: onRotateStart == null ? null : (_) => onRotateStart!(),
        onPanEnd: onRotateEnd == null ? null : (_) => onRotateEnd!(),
        onPanUpdate: (d) {
          final pointer = Offset(left + d.localPosition.dx, top + d.localPosition.dy);
          onRotate(rotationForHandle(center, pointer));
        },
        child: Center(
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: palette.handleColor,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: const [
                BoxShadow(color: Color(0x42000000), blurRadius: 6, offset: Offset(0, 2)),
              ],
            ),
            child: const Icon(Icons.rotate_right, size: 14, color: Colors.white),
          ),
        ),
      ),
    );
  }
}

/// The surface shared by the floating contextual bars: a quiet dark panel
/// with a soft edge, matching the editor chrome in both themes.
class _BarSurface extends StatelessWidget {
  final Widget child;

  const _BarSurface({required this.child});

  @override
  Widget build(BuildContext context) {
    final palette = EditorPalette.of(context);
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: palette.barSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.barForeground.withValues(alpha: 0.08)),
          boxShadow: const [
            BoxShadow(color: Color(0x1F111827), blurRadius: 18, offset: Offset(0, 6)),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// Floating action bar shown when a single annotation is selected.
///
/// Compact and contextual: the primary action for the selected type
/// (Edit / Properties / Style), Move/Resize (which is also where handles
/// appear), Duplicate, Delete and Deselect. Less-used actions (copy,
/// z-order) live behind one overflow menu so the bar never sprawls.
class EditorSelectionActionBar extends StatelessWidget {
  final bool showTextActions;
  final bool showShapeActions;
  final VoidCallback? onEditText;
  final VoidCallback? onTextDecrease;
  final VoidCallback? onTextIncrease;
  final VoidCallback? onPickTextColor;
  final VoidCallback? onEditShapeStyle;

  /// Opens a form field's properties; shown when set.
  final VoidCallback? onEditField;
  final VoidCallback onCopy;
  final VoidCallback onDuplicate;
  final VoidCallback onBringToFront;
  final VoidCallback onSendToBack;
  final VoidCallback onDelete;
  final VoidCallback onDeselect;

  /// Toggles the explicit Move/Resize (transform) mode — the only state in
  /// which handles and the bounding box are shown.
  final bool transformMode;
  final VoidCallback? onToggleTransform;

  const EditorSelectionActionBar({
    super.key,
    required this.showTextActions,
    required this.showShapeActions,
    this.onEditText,
    this.onEditField,
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
    this.transformMode = false,
    this.onToggleTransform,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = EditorPalette.of(context);
    return Positioned(
      top: 8,
      right: 8,
      child: _BarSurface(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showTextActions && onEditText != null)
              EditorMiniButton(icon: Icons.edit, tooltip: l10n.editText, onTap: onEditText!),
            if (showTextActions && onEditText != null) _divider(palette),
            if (onEditField != null)
              EditorMiniButton(icon: Icons.tune, tooltip: l10n.fieldProperties, onTap: onEditField!),
            if (onEditField != null) _divider(palette),
            if (showShapeActions)
              EditorMiniButton(icon: Icons.tune, tooltip: l10n.style, onTap: onEditShapeStyle!),
            if (showShapeActions) _divider(palette),
            if (onToggleTransform != null) ...[
              Tooltip(
                message: l10n.moveResize,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onToggleTransform!();
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: transformMode ? palette.handleColor : palette.barForeground.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Icon(
                          Icons.open_in_full,
                          size: 15,
                          color: transformMode ? Colors.white : palette.barForeground,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              _divider(palette),
            ],
            EditorMiniButton(icon: Icons.copy_all, tooltip: l10n.duplicate, onTap: onDuplicate),
            _OverflowMenu(
              items: [
                _OverflowItem(icon: Icons.content_copy, label: l10n.copy, onTap: onCopy),
                _OverflowItem(icon: Icons.flip_to_front, label: l10n.bringToFront, onTap: onBringToFront),
                _OverflowItem(icon: Icons.flip_to_back, label: l10n.sendToBack, onTap: onSendToBack),
                if (showTextActions) ...[
                  _OverflowItem(icon: Icons.text_decrease, label: 'A\u2212', onTap: onTextDecrease!),
                  _OverflowItem(icon: Icons.text_increase, label: 'A+', onTap: onTextIncrease!),
                  _OverflowItem(icon: Icons.palette_outlined, label: l10n.colorTitle, onTap: onPickTextColor!),
                ],
              ],
            ),
            _divider(palette),
            EditorMiniButton(
                icon: Icons.delete_outline, tooltip: l10n.delete, onTap: onDelete),
            EditorMiniButton(icon: Icons.close, tooltip: l10n.deselect, onTap: onDeselect),
          ],
        ),
      ),
    );
  }

  Widget _divider(EditorPalette palette) => SizedBox(
        height: 24,
        child: VerticalDivider(color: palette.barForeground.withValues(alpha: 0.14), width: 4, thickness: 1),
      );
}

/// One entry of the overflow menu in the selection bar.
class _OverflowItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _OverflowItem({required this.icon, required this.label, required this.onTap});
}

class _OverflowMenu extends StatelessWidget {
  final List<_OverflowItem> items;

  const _OverflowMenu({required this.items});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = EditorPalette.of(context);
    return PopupMenuButton<void>(
      tooltip: l10n.moreActions,
      color: palette.barSurface,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: PopupMenuPosition.under,
      offset: const Offset(0, 6),
      constraints: const BoxConstraints(minWidth: 190),
      icon: Icon(Icons.more_horiz, size: 22, color: palette.barForeground),
      padding: EdgeInsets.zero,
      onSelected: (_) {},
      itemBuilder: (ctx) => [
        for (final it in items)
          PopupMenuItem<void>(
            height: 44,
            onTap: it.onTap,
            child: Row(children: [
              Icon(it.icon, size: 19, color: palette.barForeground.withValues(alpha: 0.9)),
              const SizedBox(width: 12),
              Flexible(child: Text(it.label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: palette.barForeground))),
            ]),
          ),
      ],
    );
  }
}

/// Floating action bar shown when multiple annotations are selected (marquee).
/// Align / distribute are grouped behind two compact menus.
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
    final palette = EditorPalette.of(context);
    return Positioned(
      top: 8,
      left: 8,
      right: 8,
      child: _BarSurface(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8, right: 4),
                child: Text(
                  l10n.nSelected(count),
                  style: TextStyle(
                    color: palette.barForeground,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _divider(palette),
              PopupMenuButton<String>(
                tooltip: l10n.alignTools,
                color: palette.barSurface,
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                position: PopupMenuPosition.under,
                offset: const Offset(0, 6),
                constraints: const BoxConstraints(minWidth: 190),
                icon: Icon(Icons.align_horizontal_left, size: 21, color: palette.barForeground),
                padding: EdgeInsets.zero,
                onSelected: (_) {},
                itemBuilder: (ctx) => [
                  _alignItem(palette.barForeground, 'left', Icons.align_horizontal_left, l10n.alignLeft, onAlignLeft),
                  _alignItem(palette.barForeground, 'center', Icons.align_horizontal_center, l10n.alignCenter, onAlignCenter),
                  _alignItem(palette.barForeground, 'right', Icons.align_horizontal_right, l10n.alignRight, onAlignRight),
                  _alignItem(palette.barForeground, 'top', Icons.align_vertical_top, l10n.alignTop, onAlignTop),
                  _alignItem(palette.barForeground, 'middle', Icons.align_vertical_center, l10n.alignMiddle, onAlignMiddle),
                  _alignItem(palette.barForeground, 'bottom', Icons.align_vertical_bottom, l10n.alignBottom, onAlignBottom),
                ],
              ),
              _divider(palette),
              PopupMenuButton<String>(
                tooltip: l10n.distributeTools,
                color: palette.barSurface,
                elevation: 6,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                position: PopupMenuPosition.under,
                offset: const Offset(0, 6),
                constraints: const BoxConstraints(minWidth: 190),
                icon: Icon(Icons.horizontal_distribute, size: 21, color: palette.barForeground),
                padding: EdgeInsets.zero,
                onSelected: (_) {},
                itemBuilder: (ctx) => [
                  _alignItem(palette.barForeground, 'dh', Icons.horizontal_distribute, l10n.distributeH, onDistributeH),
                  _alignItem(palette.barForeground, 'dv', Icons.vertical_distribute, l10n.distributeV, onDistributeV),
                ],
              ),
              _divider(palette),
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
    );
  }

  /// [fg] is the bar's text colour: the menu sits on the bar's dark surface
  /// in both themes, so the theme's default text colour would vanish.
  PopupMenuItem<String> _alignItem(Color fg, String value, IconData icon, String label, VoidCallback onTap) {
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      onTap: onTap,
      child: Row(children: [
        Icon(icon, size: 19, color: fg),
        const SizedBox(width: 12),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, color: fg))),
      ]),
    );
  }

  Widget _divider(EditorPalette palette) => SizedBox(
        height: 24,
        child: VerticalDivider(color: palette.barForeground.withValues(alpha: 0.14), width: 6, thickness: 1),
      );
}
