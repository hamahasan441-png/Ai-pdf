import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/core/theme/motion.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_mode.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_design.dart';

/// The editor's bottom bar: one entry per workspace. The active one gets a
/// quiet pill and the single accent colour; the rest stay grey.
class EditorModeBar extends StatelessWidget {
  final EditorMode mode;
  final ValueChanged<EditorMode> onChanged;

  const EditorModeBar({super.key, required this.mode, required this.onChanged});

  static const double height = 64;

  static IconData iconOf(EditorMode m) => switch (m) {
        EditorMode.view => Icons.visibility_outlined,
        EditorMode.annotate => Icons.edit_outlined,
        EditorMode.text => Icons.title,
        EditorMode.sign => Icons.draw_outlined,
        EditorMode.pages => Icons.grid_view_outlined,
      };

  static String labelOf(EditorMode m, AppLocalizations l10n) => switch (m) {
        EditorMode.view => l10n.modeView,
        EditorMode.annotate => l10n.modeAnnotate,
        EditorMode.text => l10n.modeText,
        EditorMode.sign => l10n.modeSign,
        EditorMode.pages => l10n.modePages,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final palette = EditorPalette.of(context);
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final m in EditorMode.values)
            Expanded(
              child: _ModeButton(
                icon: iconOf(m),
                label: labelOf(m, l10n),
                active: m == mode,
                palette: palette,
                onTap: () {
                  if (m == mode) return;
                  HapticFeedback.selectionClick();
                  onChanged(m);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final EditorPalette palette;
  final VoidCallback onTap;

  const _ModeButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final duration = Motion.of(context, Motion.quick);
    return Semantics(
      button: true,
      selected: active,
      label: label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: duration,
              curve: Motion.enter,
              width: 48,
              height: 28,
              decoration: BoxDecoration(
                color: active ? palette.activePill : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 21, color: active ? palette.accent : palette.barMuted),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: duration,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? palette.barForeground : palette.barMuted,
              ),
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
