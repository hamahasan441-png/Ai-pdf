import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Formatting bar shown above the keyboard while a text box is being typed in.
///
/// Bold, italic, underline and colour apply to the selected characters when
/// there is a selection, otherwise to the whole box. Font, size, alignment,
/// direction, line spacing and wrapping always apply to the whole box.
/// Buttons show the box's current state.
class EditorRichTextToolbar extends StatelessWidget {
  final bool hasFocus;
  final bool hasSelection;

  /// The box being edited; its style drives the active states.
  final TextAnnotation? box;
  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onUnderline;
  final VoidCallback onColor;
  final ValueChanged<String?>? onFont;
  final ValueChanged<int>? onSizeStep;
  final ValueChanged<TextAlign>? onAlign;
  final VoidCallback? onToggleRtl;
  final ValueChanged<double>? onLineHeight;
  final VoidCallback? onToggleWrap;

  const EditorRichTextToolbar({
    super.key,
    required this.hasFocus,
    required this.hasSelection,
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onColor,
    this.box,
    this.onFont,
    this.onSizeStep,
    this.onAlign,
    this.onToggleRtl,
    this.onLineHeight,
    this.onToggleWrap,
  });

  /// Families the editor can draw on screen and embed on export.
  static const fonts = <String?>[null, 'serif', 'monospace', 'NotoSansArabic', 'Vazirmatn'];

  static String fontLabel(AppLocalizations? l10n, String? family) {
    switch (family) {
      case null:
        return l10n?.fontDefault ?? 'Default';
      case 'serif':
        return l10n?.fontSerif ?? 'Serif';
      case 'monospace':
        return l10n?.fontMono ?? 'Monospace';
      case 'NotoSansArabic':
        return 'Noto Sans Arabic';
      default:
        return family;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!hasFocus) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final b = box;
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                if (onFont != null)
                  PopupMenuButton<String>(
                    tooltip: l10n?.font ?? 'Font',
                    onSelected: (v) => onFont!(v.isEmpty ? null : v),
                    itemBuilder: (_) => [
                      for (final f in fonts)
                        CheckedPopupMenuItem(
                          value: f ?? '',
                          checked: b?.fontFamily == f,
                          child: Text(fontLabel(l10n, f), style: TextStyle(fontFamily: f)),
                        ),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        const Icon(Icons.font_download_outlined, color: Colors.white, size: 20),
                        const SizedBox(width: 4),
                        Text(fontLabel(l10n, b?.fontFamily), style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ]),
                    ),
                  ),
                if (onSizeStep != null) ...[
                  _btn(Icons.text_decrease, l10n?.textSmaller ?? 'Smaller', () => onSizeStep!(-1)),
                  _btn(Icons.text_increase, l10n?.textLarger ?? 'Larger', () => onSizeStep!(1)),
                  _divider(),
                ],
                _btn(Icons.format_bold, l10n?.bold ?? 'Bold', onBold, active: !hasSelection && (b?.bold ?? false)),
                _btn(Icons.format_italic, l10n?.italic ?? 'Italic', onItalic, active: !hasSelection && (b?.italic ?? false)),
                _btn(Icons.format_underline, l10n?.underline ?? 'Underline', onUnderline,
                    active: !hasSelection && (b?.underline ?? false)),
                IconButton(
                  tooltip: l10n?.colorText ?? 'Text colour',
                  onPressed: onColor,
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  icon: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.format_color_text, color: Colors.white, size: 20),
                    Container(
                      width: 20,
                      height: 4,
                      decoration: BoxDecoration(
                        color: b?.color ?? Colors.black,
                        border: Border.all(color: Colors.white54, width: 0.5),
                      ),
                    ),
                  ]),
                ),
                if (onAlign != null) ...[
                  _divider(),
                  _btn(Icons.format_align_left, l10n?.alignLeft ?? 'Align left', () => onAlign!(TextAlign.left),
                      active: b?.textAlign == TextAlign.left),
                  _btn(Icons.format_align_center, l10n?.alignCenter ?? 'Align center', () => onAlign!(TextAlign.center),
                      active: b?.textAlign == TextAlign.center),
                  _btn(Icons.format_align_right, l10n?.alignRight ?? 'Align right', () => onAlign!(TextAlign.right),
                      active: b?.textAlign == TextAlign.right),
                  _btn(Icons.format_align_justify, l10n?.alignJustify ?? 'Justify', () => onAlign!(TextAlign.justify),
                      active: b?.textAlign == TextAlign.justify),
                ],
                if (onToggleRtl != null)
                  _btn(Icons.format_textdirection_r_to_l, l10n?.textRightToLeft ?? 'Right to left', onToggleRtl!,
                      active: b?.textDirection == TextDirection.rtl),
                if (onLineHeight != null)
                  PopupMenuButton<double>(
                    tooltip: l10n?.lineSpacing ?? 'Line spacing',
                    onSelected: onLineHeight,
                    itemBuilder: (_) => [
                      for (final v in const [1.0, 1.15, 1.5, 2.0])
                        CheckedPopupMenuItem(value: v, checked: (b?.lineHeight ?? 1) == v, child: Text('$v')),
                    ],
                    icon: const Icon(Icons.format_line_spacing, color: Colors.white, size: 22),
                  ),
                if (onToggleWrap != null)
                  _btn(Icons.wrap_text, l10n?.wrapText ?? 'Wrap in a fixed width', onToggleWrap!,
                      active: b?.width != null),
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

  Widget _btn(IconData icon, String tooltip, VoidCallback onTap, {bool active = false}) {
    return IconButton(
      icon: Icon(icon, color: active ? Colors.lightBlueAccent : Colors.white, size: 22),
      tooltip: tooltip,
      onPressed: onTap,
      isSelected: active,
      style: active ? IconButton.styleFrom(backgroundColor: Colors.white24) : null,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}
