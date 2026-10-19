import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A slim bar over the page that names the mode the editor is in (such as
/// Edit text), says what a tap does, and ends the mode with Done. It stays
/// while the mode is on, instead of a message that disappears.
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
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Color(0x1F1B2130), blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Material(
        color: cs.primary,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: cs.onPrimary.withValues(alpha: 0.16), shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: cs.onPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                    Text(
                      hint,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.85), fontSize: 12.5),
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
                  backgroundColor: cs.onPrimary,
                  foregroundColor: cs.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: const Size(0, 36),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
