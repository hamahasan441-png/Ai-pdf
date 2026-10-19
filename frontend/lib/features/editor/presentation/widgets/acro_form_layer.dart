import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';

/// One widget of a form field placed on the shown page (0..1 rect).
typedef PlacedAcroWidget = ({AcroField field, AcroWidget widget, Rect rect});

/// The text field being typed in, drawn in place of its value.
class AcroInlineEditing {
  final String fieldName;
  final int widgetObjNum;
  final TextEditingController controller;
  final FocusNode focusNode;
  final TextInputType keyboard;
  final List<TextInputFormatter> formatters;
  final ValueChanged<String> onSubmitted;

  const AcroInlineEditing({
    required this.fieldName,
    required this.widgetObjNum,
    required this.controller,
    required this.focusNode,
    required this.keyboard,
    this.formatters = const [],
    required this.onSubmitted,
  });
}

/// The PDF's own form fields drawn over the page, each showing its current
/// value. Tapping a field calls [onTap] when [interactive].
///
/// The value is drawn on an opaque background, so the result does not
/// depend on whether the page renderer drew the file's own appearances, and
/// an edited value never shows on top of the old one.
///
/// The field in focus ([focusName] / [focusObjNum]) gets a dashed outline;
/// a text field being typed in ([editing]) turns white and takes the
/// keyboard right there, at the field's size and position, so it zooms and
/// scrolls with the page.
class AcroFormLayer extends StatelessWidget {
  final List<PlacedAcroWidget> widgets;
  final Map<String, Object> edits;
  final bool interactive;
  final void Function(AcroField field, AcroWidget widget) onTap;
  final String? focusName;
  final int? focusObjNum;
  final AcroInlineEditing? editing;

  const AcroFormLayer({
    super.key,
    required this.widgets,
    required this.edits,
    required this.interactive,
    required this.onTap,
    this.focusName,
    this.focusObjNum,
    this.editing,
  });

  static const fill = Color(0xFFD9E4FF);
  static const border = Color(0xFF5B7FD9);
  static const requiredBorder = Color(0xFFD32F2F);
  static const checkColor = Color(0xFFC62828);

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
                child: _field(context, p, size),
              ),
          ],
        ),
      );
    });
  }

  /// Screen pixels per PDF point for [p] (rotation does not matter).
  static double _scale(PlacedAcroWidget p, Size page) {
    final area = p.widget.width * p.widget.height;
    if (area <= 0) return 1;
    return math.sqrt((p.rect.width * page.width * p.rect.height * page.height) / area);
  }

  /// The text size the field asks for (/DA), or one that fits its height.
  static double fontSizeFor(PlacedAcroWidget p, Size page) {
    final s = _scale(p, page);
    final h = p.rect.height * page.height;
    if (p.field.fontSize > 0) return p.field.fontSize * s;
    return p.field.multiline ? (10 * s).clamp(4.0, h) : (h * 0.62).clamp(4.0, 40.0);
  }

  Widget _field(BuildContext context, PlacedAcroWidget p, Size page) {
    final f = p.field;
    final value = fieldValue(f, edits);
    final editable = f.fillable;
    final missing = editable && f.required && fieldValueEmpty(value);
    final focused = f.name == focusName && p.widget.objNum == focusObjNum;
    final typing = editing != null && editing!.fieldName == f.name && editing!.widgetObjNum == p.widget.objNum;
    final round = f.kind == AcroFieldKind.radio;
    final button = f.kind == AcroFieldKind.checkbox || round;
    final on = f.kind == AcroFieldKind.checkbox ? value != 'Off' : (round && value == p.widget.onState);
    final Widget content = switch (f.kind) {
      AcroFieldKind.checkbox => _mark(on ? Icons.check : null, color: checkColor),
      AcroFieldKind.radio => _mark(on ? Icons.circle : null, round: true, color: border),
      AcroFieldKind.text || AcroFieldKind.choice => typing ? _input(p, page) : _text(p, value, page),
      _ => const SizedBox.shrink(),
    };
    final l10n = AppLocalizations.of(context);
    final label = l10n == null
        ? f.name
        : (f.required ? '${l10n.fieldRequired}. ' : '') +
            switch (f.kind) {
              AcroFieldKind.checkbox => l10n.formCheckbox(f.name, on ? l10n.formChecked : l10n.formNotChecked),
              AcroFieldKind.radio => [
                  l10n.formOption(f.name, p.widget.onState ?? ''),
                  if (on) l10n.formSelected,
                ].join(', '),
              _ => '${f.name}: ${fieldDisplayText(f, value)}',
            };
    final Color borderColor;
    if (!editable) {
      borderColor = Colors.black26;
    } else if (button && on) {
      borderColor = f.kind == AcroFieldKind.checkbox ? checkColor : border;
    } else {
      borderColor = missing ? requiredBorder : border;
    }
    Widget box = AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: !editable ? const Color(0xFFEDEDED) : (typing || (button && !on) ? Colors.white : fill),
        border: Border.all(color: borderColor, width: missing || (button && on) ? 1.4 : 1),
        borderRadius: round ? null : BorderRadius.circular(button ? 2 : 1.5),
        shape: round ? BoxShape.circle : BoxShape.rectangle,
      ),
      child: f.required && editable && !button && !typing
          ? Stack(children: [
              Positioned.fill(child: content),
              const Positioned(
                right: 1,
                top: 0,
                child: Text('*', style: TextStyle(color: requiredBorder, fontSize: 12, height: 1)),
              ),
            ])
          : content,
    );
    if (focused) {
      // The field in focus: a dashed outline just outside it.
      box = CustomPaint(
        foregroundPainter: _DashedOutline(round: round),
        child: box,
      );
    }
    return Semantics(
      button: editable,
      enabled: editable,
      focused: focused,
      label: label,
      excludeSemantics: !typing,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: editable && !typing ? () => onTap(f, p.widget) : null,
        child: box,
      ),
    );
  }

  Widget _mark(IconData? icon, {bool round = false, required Color color}) => icon == null
      ? const SizedBox.expand()
      : FittedBox(
          child: Padding(
            padding: EdgeInsets.all(round ? 6 : 1),
            child: Icon(icon, color: color, weight: 700),
          ),
        );

  TextAlign _align(AcroField f) => switch (f.quadding) {
        1 => TextAlign.center,
        2 => TextAlign.right,
        _ => TextAlign.left,
      };

  Widget _input(PlacedAcroWidget p, Size page) {
    final e = editing!;
    final f = p.field;
    final size = fontSizeFor(p, page);
    // Field text follows the page's scale, not the system font size.
    return MediaQuery.withNoTextScaling(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Align(
          alignment: f.multiline ? Alignment.topCenter : Alignment.center,
          child: TextField(
            controller: e.controller,
            focusNode: e.focusNode,
            keyboardType: e.keyboard,
            inputFormatters: [
              ...e.formatters,
              if (f.maxLen != null && f.maxLen! > 0) LengthLimitingTextInputFormatter(f.maxLen),
            ],
            textInputAction: f.multiline ? TextInputAction.newline : TextInputAction.next,
            maxLines: f.multiline ? null : 1,
            expands: f.multiline,
            textAlign: _align(f),
            textAlignVertical: f.multiline ? TextAlignVertical.top : TextAlignVertical.center,
            onSubmitted: f.multiline ? null : e.onSubmitted,
            cursorWidth: (size * 0.08).clamp(1.0, 2.0),
            style: TextStyle(fontSize: size, color: Colors.black, height: 1.1),
            decoration: const InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ),
    );
  }

  Widget _text(PlacedAcroWidget p, Object value, Size page) {
    final f = p.field;
    final text = fieldDisplayText(f, value);
    final size = fontSizeFor(p, page);
    final shown = Text(
      text,
      maxLines: f.multiline ? null : 1,
      textAlign: _align(f),
      overflow: f.multiline ? TextOverflow.clip : TextOverflow.visible,
      softWrap: f.multiline,
      textScaler: TextScaler.noScaling,
      style: TextStyle(fontSize: size, color: Colors.black, height: 1.1),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        crossAxisAlignment: f.multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: f.multiline
                ? shown
                // A long value shrinks to fit the box, as auto-size does.
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: switch (f.quadding) {
                      1 => Alignment.center,
                      2 => Alignment.centerRight,
                      _ => Alignment.centerLeft,
                    },
                    child: shown,
                  ),
          ),
          if (f.combo) Icon(Icons.arrow_drop_down, size: size + 4, color: Colors.black54),
        ],
      ),
    );
  }
}

/// A dashed outline around a focused field, drawn just outside its box.
class _DashedOutline extends CustomPainter {
  final bool round;

  _DashedOutline({required this.round});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1B2130)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final r = (Offset.zero & size).inflate(2);
    final path = round ? (Path()..addOval(r)) : (Path()..addRect(r));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 3, metric.length)), paint);
        d += 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutline old) => old.round != round;
}
