import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_pdf/features/editor/presentation/widgets/editor_design.dart';

/// A slim bar over the page that names the mode the editor is in (such as
/// Edit text), says what a tap does, and ends the mode with Done. It stays
/// while the mode is on, instead of a message that disappears.
///
/// The bar is a quiet card, not a full-bleed accent, so a long editing
/// session does not shout at the page.
class EditorModeBanner extends StatelessWidget {
  final IconData icon;
  final String title;
  final String hint;
  final String doneLabel;
  final VoidCallback onDone;

  const EditorModeBanner({
    super.key,
    required this.icon,
    required this.title,
    required this.hint,
    required this.doneLabel,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final palette = EditorPalette.of(context);
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
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 8, 8),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: palette.activePill, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: palette.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: palette.barForeground, fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.barMuted, fontSize: 12.5, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  onDone();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.onAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
                child: Text(doneLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
