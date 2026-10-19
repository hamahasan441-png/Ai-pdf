import 'dart:ui' show Offset, Rect;

import 'package:flutter/material.dart' show Color;

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Form field sub-types (mirrors the detected field types).
enum FormFieldKind {
  text,
  number,
  date,
  email,
  phone,
  name,
  signature,
  checkbox,
  radio,
  combobox,
}

/// A form field the user adds to the page.
///
/// It is saved with the page's other marks, drawn with a field frame, and
/// exported as a real fillable PDF field (an AcroForm widget) that other
/// readers can fill: text, number, date, e-mail, phone and name become text
/// fields, checkbox and radio become check boxes, combobox a drop-down list
/// with [options], signature an empty signature field. [label] is the
/// field's name in the PDF.
///
/// ### Coordinate system
/// [pos] is the top-left in normalised 0..1 page coordinates.
/// [width] / [height] are normalised fractions of the page.
class FormFieldAnnotation extends EditorAnnotation {
  Offset pos;
  double width;
  double height;
  FormFieldKind fieldKind;
  String label;
  String value;
  bool required;
  bool checked; // for checkbox / radio

  /// Choices of a combobox.
  List<String> options;

  /// A text field that takes several lines.
  bool multiline;
  Color borderColor;
  Color fillColor;
  double fontSize; // normalised to page height (like TextAnnotation.size)

  FormFieldAnnotation({
    required this.pos,
    required this.width,
    required this.height,
    required this.fieldKind,
    required this.label,
    this.value = '',
    this.required = false,
    this.checked = false,
    this.options = const [],
    this.multiline = false,
    this.borderColor = const Color(0xFF2563EB),
    this.fillColor = const Color(0x1A2563EB),
    this.fontSize = 0.018,
    super.id,
  });

  /// Whether this field is a checkable (toggle) type.
  bool get isCheckable => fieldKind == FormFieldKind.checkbox || fieldKind == FormFieldKind.radio;

  /// Create from a detected field (ephemeral → persistent annotation).
  factory FormFieldAnnotation.fromDetected({
    required Offset pos,
    required double width,
    required double height,
    required String label,
    required FormFieldKind kind,
  }) {
    return FormFieldAnnotation(
      pos: pos,
      width: width,
      height: height,
      fieldKind: kind,
      label: label,
    );
  }

  @override
  Rect get bounds => Rect.fromLTWH(pos.dx, pos.dy, width, height);

  @override
  void translate(Offset delta) {
    pos = clampOffset01(pos + delta);
  }

  @override
  void scaleTo(Rect next) {
    pos = Offset(next.left.clamp(0.0, 1.0), next.top.clamp(0.0, 1.0));
    width = next.width.abs().clamp(0.02, 1.0);
    height = next.height.abs().clamp(0.01, 1.0);
  }

  @override
  FormFieldAnnotation clone({double shift = 0, String? id}) {
    final c = FormFieldAnnotation(
      pos: Offset(pos.dx + shift, pos.dy + shift),
      width: width,
      height: height,
      fieldKind: fieldKind,
      label: label,
      value: value,
      required: required,
      checked: checked,
      options: List.of(options),
      multiline: multiline,
      borderColor: borderColor,
      fillColor: fillColor,
      fontSize: fontSize,
      id: id,
    );
    c.copyBaseFrom(this);
    return c;
  }

  @override
  void restoreFrom(FormFieldAnnotation o) {
    pos = o.pos;
    width = o.width;
    height = o.height;
    fieldKind = o.fieldKind;
    label = o.label;
    value = o.value;
    required = o.required;
    checked = o.checked;
    options = List.of(o.options);
    multiline = o.multiline;
    borderColor = o.borderColor;
    fillColor = o.fillColor;
    fontSize = o.fontSize;
    copyBaseFrom(o);
  }
}
