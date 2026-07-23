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
  final VoidCallback? onAlignLeft;
  final VoidCallback? onAlignCenter;
  final VoidCallback? onAlignRight;
  final VoidCallback? onToggleRtl;

  const EditorRichTextToolbar({
    super.key,
    required this.hasFocus,
    required this.hasSelection,
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onColor,
    this.onAlignLeft,
    this.onAlignCenter,
    this.onAlignRight,
    this.onToggleRtl,
  });

  @override
  Widget build(BuildContext context) {
    if (!hasFocus) return const SizedBox.shrink();
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (hasSelection) ...[
                  _btn(Icons.format_bold, 'Bold', onBold),
                  _btn(Icons.format_italic, 'Italic', onItalic),
                  _btn(Icons.format_underline, 'Underline', onUnderline),
                  _btn(Icons.format_color_text, 'Colour', onColor),
                  _divider(),
                ],
                _btn(Icons.format_align_left, 'Left', onAlignLeft ?? () {}),
                _btn(Icons.format_align_center, 'Center', onAlignCenter ?? () {}),
                _btn(Icons.format_align_right, 'Right', onAlignRight ?? () {}),
                if (onToggleRtl != null) ...[
                  _divider(),
                  _btn(Icons.format_textdirection_r_to_l, 'RTL', onToggleRtl!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 24,
        color: Colors.grey.shade700,
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );

  Widget _btn(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: Colors.white, size: 22),
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}
