import 'package:flutter/material.dart';

/// A compact floating toolbar for per-selection rich text formatting.
///
/// Shown above the keyboard when the inline text editor has an active text
/// selection (not collapsed). The user taps bold/italic/underline/colour to
/// apply styling to the currently selected range.
class EditorRichTextToolbar extends StatelessWidget {
  final bool hasFocus;
  final bool hasSelection;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onUnderline;
  final VoidCallback onColor;

  const EditorRichTextToolbar({
    super.key,
    required this.hasFocus,
    required this.hasSelection,
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onColor,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasFocus || !hasSelection) return const SizedBox.shrink();
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Material(
        elevation: 8,
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _btn(Icons.format_bold, 'Bold', onBold),
                _btn(Icons.format_italic, 'Italic', onItalic),
                _btn(Icons.format_underline, 'Underline', onUnderline),
                _btn(Icons.format_color_text, 'Colour', onColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _btn(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 22),
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}
