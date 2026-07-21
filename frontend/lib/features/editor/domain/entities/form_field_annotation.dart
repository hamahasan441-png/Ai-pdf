import 'dart:ui' show Offset;

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
}
