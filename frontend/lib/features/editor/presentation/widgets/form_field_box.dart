import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/form_field_annotation.dart';

/// How a field the user added looks on the page: its frame and fill, its
/// value (or its name, faint, while empty), a tick for a ticked check box,
/// a drop-down arrow, and a red mark when it is required. Taps go through to
/// the canvas, which selects, moves and resizes it like any other mark.
class FormFieldBox extends StatelessWidget {
  /// Label text of an empty field: readable on the white page whatever the
  /// (often very light) frame colour is.
  static const _placeholder = Color(0xFF6B7488);

  final FormFieldAnnotation field;
  final Size page;

  const FormFieldBox({super.key, required this.field, required this.page});

  @override
  Widget build(BuildContext context) {
    final f = field;
    final w = f.width * page.width;
    final h = f.height * page.height;
    final fontSize = (h * 0.6).clamp(6.0, 18.0);
    final empty = f.value.isEmpty;
    Widget content;
    switch (f.fieldKind) {
      case FormFieldKind.checkbox || FormFieldKind.radio:
        content = f.checked ? Icon(Icons.check, size: h * 0.9, color: Colors.black) : const SizedBox.shrink();
      case FormFieldKind.signature:
        content = Row(children: [
          Icon(Icons.draw_outlined, size: (h * 0.5).clamp(8.0, 20.0), color: _placeholder),
          const SizedBox(width: 4),
          Flexible(child: _label(f.label, fontSize, _placeholder)),
        ]);
      default:
        content = Row(children: [
          Expanded(
            child: empty
                ? _label(f.label, fontSize, _placeholder)
                : Text(
                    f.value,
                    maxLines: f.multiline ? null : 1,
                    overflow: TextOverflow.clip,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(fontSize: fontSize, color: Colors.black, height: 1.1),
                  ),
          ),
          if (f.fieldKind == FormFieldKind.combobox) Icon(Icons.arrow_drop_down, size: fontSize * 1.4),
        ]);
    }
    return IgnorePointer(
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: f.fillColor,
                border: Border.all(color: f.borderColor),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Align(alignment: f.multiline ? Alignment.topLeft : Alignment.centerLeft, child: content),
              ),
            ),
          ),
          if (f.required)
            const Positioned(right: 1, top: 0, child: Text('*', style: TextStyle(color: Colors.red, fontSize: 12, height: 1))),
        ]),
      ),
    );
  }

  Widget _label(String text, double size, Color color) => Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textScaler: TextScaler.noScaling,
        style: TextStyle(fontSize: size, color: color, fontStyle: FontStyle.italic),
      );
}
