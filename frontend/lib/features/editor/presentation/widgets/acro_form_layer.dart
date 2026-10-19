import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';

/// One widget of a form field placed on the shown page (0..1 rect).
typedef PlacedAcroWidget = ({AcroField field, AcroWidget widget, Rect rect});

/// The PDF's own form fields drawn over the page, each showing its current
/// value. Tapping a field calls [onTap] when [interactive].
///
/// The value is drawn on an opaque background, so the result does not
/// depend on whether the page renderer drew the file's own appearances, and
/// an edited value never shows on top of the old one.
class AcroFormLayer extends StatelessWidget {
  final List<PlacedAcroWidget> widgets;
  final Map<String, Object> edits;
  final bool interactive;
  final void Function(AcroField field, AcroWidget widget) onTap;

  const AcroFormLayer({
    super.key,
    required this.widgets,
    required this.edits,
    required this.interactive,
    required this.onTap,
  });

  static const fill = Color(0xFFE3ECFD);
  static const border = Color(0xFF6B8EDB);
  static const requiredBorder = Color(0xFFD32F2F);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final size = Size(c.maxWidth, c.maxHeight);
      return IgnorePointer(
        ignoring: !interactive,
        child: Stack(
          children: [
            for (final p in widgets)
              Positioned(
                left: p.rect.left * size.width,
                top: p.rect.top * size.height,
                width: p.rect.width * size.width,
                height: p.rect.height * size.height,
                child: _field(context, p),
              ),
          ],
        ),
      );
    });
  }

  Widget _field(BuildContext context, PlacedAcroWidget p) {
    final f = p.field;
    final value = fieldValue(f, edits);
    final editable = f.fillable;
    final missing = editable && f.required && fieldValueEmpty(value);
    final Widget content = switch (f.kind) {
      AcroFieldKind.checkbox => _mark(value != 'Off' ? Icons.check : null),
      AcroFieldKind.radio => _mark(value == p.widget.onState ? Icons.circle : null, round: true),
      AcroFieldKind.text || AcroFieldKind.choice => _text(f, value),
      _ => const SizedBox.shrink(),
    };
    final l10n = AppLocalizations.of(context);
    final label = l10n == null
        ? f.name
        : switch (f.kind) {
            AcroFieldKind.checkbox => l10n.formCheckbox(f.name, value != 'Off' ? l10n.formChecked : l10n.formNotChecked),
            AcroFieldKind.radio => [
                l10n.formOption(f.name, p.widget.onState ?? ''),
                if (value == p.widget.onState) l10n.formSelected,
              ].join(', '),
            _ => '${f.name}: ${fieldDisplayText(f, value)}',
          };
    return Semantics(
      button: editable,
      enabled: editable,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: editable ? () => onTap(f, p.widget) : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: editable ? fill : const Color(0xFFEDEDED),
            // A required field still empty is outlined in red.
            border: Border.all(
              color: !editable ? Colors.black26 : (missing ? requiredBorder : border),
              width: missing ? 1.4 : 0.8,
            ),
            shape: f.kind == AcroFieldKind.radio ? BoxShape.circle : BoxShape.rectangle,
          ),
          child: f.required && editable && f.kind != AcroFieldKind.radio
              ? Stack(children: [
                  Positioned.fill(child: content),
                  const Positioned(
                    right: 1,
                    top: 0,
                    child: Text('*', style: TextStyle(color: requiredBorder, fontSize: 12, height: 1)),
                  ),
                ])
              : content,
        ),
      ),
    );
  }

  Widget _mark(IconData? icon, {bool round = false}) => icon == null
      ? const SizedBox.expand()
      : FittedBox(
          child: Padding(
            padding: EdgeInsets.all(round ? 6 : 2),
            child: Icon(icon, color: Colors.black),
          ),
        );

  Widget _text(AcroField f, Object value) {
    final text = fieldDisplayText(f, value);
    return LayoutBuilder(builder: (context, c) {
      final h = c.maxHeight;
      final size = f.multiline ? (h / 4).clamp(6.0, 14.0) : (h * 0.6).clamp(6.0, 18.0);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Align(
          alignment: f.multiline ? AlignmentDirectional.topStart : AlignmentDirectional.centerStart,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: f.multiline ? null : 1,
                  overflow: f.multiline ? TextOverflow.clip : TextOverflow.ellipsis,
                  style: TextStyle(fontSize: size.toDouble(), color: Colors.black, height: 1.1),
                ),
              ),
              if (f.combo) Icon(Icons.arrow_drop_down, size: size.toDouble() + 4, color: Colors.black54),
            ],
          ),
        ),
      );
    });
  }
}
