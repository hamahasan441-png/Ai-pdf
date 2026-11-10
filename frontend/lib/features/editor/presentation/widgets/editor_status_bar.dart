import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/presentation/widgets/editor_design.dart';

/// The quiet strip under the page: where you are, how big the page or the
/// selection is, and the zoom. It is the same in every workspace.
class EditorStatusBar extends StatelessWidget {
  static const double height = 36;

  final String page;
  final String detail;
  final int zoom;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;

  /// Locks or unlocks the selection. Hidden when null.
  final VoidCallback? onToggleLock;
  final bool locked;

  /// Turns the selection. Hidden when null.
  final VoidCallback? onRotate;

  /// Opens the millimetre place dialog. The detail is tappable when set.
  final VoidCallback? onDetail;

  const EditorStatusBar({
    super.key,
    required this.page,
    required this.detail,
    required this.zoom,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    this.onToggleLock,
    this.locked = false,
    this.onRotate,
    this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = EditorPalette.of(context);
    final style = TextStyle(color: palette.barForeground, fontSize: 12, fontWeight: FontWeight.w600);
    final quiet = style.copyWith(fontWeight: FontWeight.w500, color: palette.barForeground.withValues(alpha: 0.72));
    return Material(
      color: palette.barSurface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: palette.hairline))),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Text(page, style: style),
                if (detail.isNotEmpty) ...[
                  Text('  ·  ', style: quiet),
                  Expanded(child: _detail(detail, quiet, palette, l10n)),
                ] else
                  const Spacer(),
                if (onToggleLock != null)
                  _icon(
                    locked ? Icons.lock : Icons.lock_open,
                    locked ? l10n.unlockObject : l10n.lockObject,
                    onToggleLock!,
                    palette,
                  ),
                if (onRotate != null) _icon(Icons.rotate_90_degrees_ccw, l10n.rotateObject, onRotate!, palette),
                _icon(Icons.remove, l10n.zoomOut, onZoomOut, palette),
                SizedBox(
                  width: 44,
                  child: Text('$zoom%', textAlign: TextAlign.center, style: style),
                ),
                _icon(Icons.add, l10n.zoomIn, onZoomIn, palette),
                _icon(Icons.fit_screen_outlined, l10n.shortcutFitPage, onFit, palette),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(String detail, TextStyle quiet, EditorPalette palette, AppLocalizations l10n) {
    final text = Text(
      detail,
      style: onDetail == null
          ? quiet
          : quiet.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: palette.barForeground.withValues(alpha: 0.45),
            ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (onDetail == null) return text;
    return Tooltip(
      message: l10n.placeBySize,
      child: InkWell(onTap: onDetail, child: text),
    );
  }

  Widget _icon(IconData icon, String tip, VoidCallback onTap, EditorPalette palette) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      tooltip: tip,
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: palette.barForeground),
    );
  }
}
