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

/// An interactive form-field overlay annotation.
///
/// Unlike the OCR-detected [DetectedField] (which is ephemeral and display-only),
/// this is a persistent, editable annotation that:
/// - Can be placed by the user or by AI field detection
/// - Stores the filled value
/// - Renders with a professional field chrome (border, label, fill color)
/// - Exports as a real form-field visual in the PDF
/// - Can be validated via [FieldValidator]
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
    borderColor = o.borderColor;
    fillColor = o.fillColor;
    fontSize = o.fontSize;
    copyBaseFrom(o);
  }
}
