import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/core/theme/motion.dart';
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
    // The scaffold does not shrink for the keyboard, so the bar has to
    // rise with it. Otherwise bold, size and colour sit underneath it
    // while a new text box is being typed.
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Positioned(
      left: 8,
      right: 8,
      bottom: keyboard + (keyboard == 0 ? 0 : 8),
      child: SafeArea(
        top: false,
        bottom: keyboard == 0,
        child: MotionReveal(from: const Offset(0, 0.4), child: hasFocus ? _bar(context) : null),
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final b = box;
    return DecoratedBox(
      key: const ValueKey('format-bar'),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [BoxShadow(color: Color(0x261B2130), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Material(
        color: cs.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cs.outlineVariant),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(6),
          child: Row(
            children: [
              if (onFont != null)
                _Group(children: [
                  PopupMenuButton<String>(
                    tooltip: l10n?.font ?? 'Font',
                    onSelected: (v) => onFont!(v.isEmpty ? null : v),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    itemBuilder: (_) => [
                      for (final f in fonts)
                        CheckedPopupMenuItem(
                          value: f ?? '',
                          checked: b?.fontFamily == f,
                          child: Text(fontLabel(l10n, f), style: TextStyle(fontFamily: f)),
                        ),
                    ],
                    child: SizedBox(
                      height: 40,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Row(children: [
                          Text(
                            fontLabel(l10n, b?.fontFamily),
                            style: TextStyle(
                              color: cs.onSurface,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              fontFamily: b?.fontFamily,
                            ),
                          ),
                          Icon(Icons.expand_more, size: 18, color: cs.onSurfaceVariant),
                        ]),
                      ),
                    ),
                  ),
                ]),
              if (onSizeStep != null)
                _Group(children: [
                  _ToolButton(Icons.text_decrease, l10n?.textSmaller ?? 'Smaller', () => onSizeStep!(-1)),
                  _ToolButton(Icons.text_increase, l10n?.textLarger ?? 'Larger', () => onSizeStep!(1)),
                ]),
              _Group(children: [
                _ToolButton(Icons.format_bold, l10n?.bold ?? 'Bold', onBold,
                    active: !hasSelection && (b?.bold ?? false)),
                _ToolButton(Icons.format_italic, l10n?.italic ?? 'Italic', onItalic,
                    active: !hasSelection && (b?.italic ?? false)),
                _ToolButton(Icons.format_underline, l10n?.underline ?? 'Underline', onUnderline,
                    active: !hasSelection && (b?.underline ?? false)),
                _ColorButton(tooltip: l10n?.colorText ?? 'Text colour', color: b?.color ?? Colors.black, onTap: onColor),
              ]),
              if (onAlign != null)
                _Group(children: [
                  for (final (align, icon, label) in [
                    (TextAlign.left, Icons.format_align_left, l10n?.alignLeft ?? 'Align left'),
                    (TextAlign.center, Icons.format_align_center, l10n?.alignCenter ?? 'Align center'),
                    (TextAlign.right, Icons.format_align_right, l10n?.alignRight ?? 'Align right'),
                    (TextAlign.justify, Icons.format_align_justify, l10n?.alignJustify ?? 'Justify'),
                  ])
                    _ToolButton(icon, label, () => onAlign!(align), active: b?.textAlign == align),
                ]),
              _Group(last: true, children: [
                if (onToggleRtl != null)
                  _ToolButton(Icons.format_textdirection_r_to_l, l10n?.textRightToLeft ?? 'Right to left', onToggleRtl!,
                      active: b?.textDirection == TextDirection.rtl),
                if (onLineHeight != null)
                  PopupMenuButton<double>(
                    tooltip: l10n?.lineSpacing ?? 'Line spacing',
                    onSelected: onLineHeight,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    itemBuilder: (_) => [
                      for (final v in const [1.0, 1.15, 1.5, 2.0])
                        CheckedPopupMenuItem(value: v, checked: (b?.lineHeight ?? 1) == v, child: Text('$v')),
                    ],
                    child: SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(Icons.format_line_spacing, size: 21, color: cs.onSurface),
                    ),
                  ),
                if (onToggleWrap != null)
                  _ToolButton(Icons.wrap_text, l10n?.wrapText ?? 'Wrap in a fixed width', onToggleWrap!,
                      active: b?.width != null),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// A run of related buttons on a soft background, with room after it.
class _Group extends StatelessWidget {
  final List<Widget> children;
  final bool last;

  const _Group({required this.children, this.last = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsetsDirectional.only(end: last ? 0 : 6),
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// A formatting button; when [active] its background fades to the accent.
class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;

  const _ToolButton(this.icon, this.tooltip, this.onTap, {this.active = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: Motion.of(context, Motion.quick),
      curve: Motion.enter,
      decoration: BoxDecoration(
        color: active ? cs.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(11),
      ),
      child: IconButton(
        icon: Icon(icon, size: 21),
        color: active ? cs.primary : cs.onSurface,
        tooltip: tooltip,
        isSelected: active,
        onPressed: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
          backgroundColor: Colors.transparent,
        ),
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// The text colour button: a letter over a swatch of the current colour.
class _ColorButton extends StatelessWidget {
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _ColorButton({required this.tooltip, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      constraints: const BoxConstraints.tightFor(width: 44, height: 44),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11))),
      icon: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.format_color_text, size: 19, color: cs.onSurface),
        AnimatedContainer(
          duration: Motion.of(context, Motion.quick),
          width: 18,
          height: 4,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: cs.outline, width: 0.5),
          ),
        ),
      ]),
    );
  }
}
