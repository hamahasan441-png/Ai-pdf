import 'package:flutter/widgets.dart';

/// Inferred type of a detected form field, so tapping it opens the right input.
enum FieldType { text, number, date, email, phone, name, signature, checkbox, radio }

/// A fillable field the app detected on the page via OCR. [rect] is the label
/// position (normalized 0..1); the value is placed just after it, at a font
/// size matched to the label's height.
class DetectedField {
  final Rect rect;
  final String label;
  final FieldType type;
  const DetectedField(this.rect, this.label, this.type);
}
