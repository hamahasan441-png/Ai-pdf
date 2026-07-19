import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/detected_field.dart';

class EditorFieldPlacement {
  final Offset pos;
  final double size;
  final String title;

  const EditorFieldPlacement({
    required this.pos,
    required this.size,
    required this.title,
  });
}

/// Placement and input helpers for detected form fields inside the editor.
class EditorFieldInputService {
  const EditorFieldInputService();

  TextAnnotation buildCheckboxAnnotation(DetectedField field, String mark) {
    final markSize = (field.rect.height * 0.80).clamp(0.012, 0.06).toDouble();
    final cx = (field.rect.left + (field.rect.width - markSize * 0.5) * 0.5)
        .clamp(0.0, 0.97)
        .toDouble();
    final cy = (field.rect.top + (field.rect.height - markSize) * 0.3)
        .clamp(0.0, 0.97)
        .toDouble();
    final color = mark == '✓' ? const Color(0xFF16A34A) : const Color(0xFFD9636B);
    return TextAnnotation(Offset(cx, cy), mark, color, markSize, true);
  }

  TextAnnotation buildRadioAnnotation(DetectedField field) {
    final dotSize = (field.rect.height * 0.70).clamp(0.010, 0.05).toDouble();
    final cx = (field.rect.left + (field.rect.width - dotSize * 0.4) * 0.5)
        .clamp(0.0, 0.97)
        .toDouble();
    final cy = (field.rect.top + (field.rect.height - dotSize) * 0.35)
        .clamp(0.0, 0.97)
        .toDouble();
    return TextAnnotation(Offset(cx, cy), '●', Colors.black, dotSize, false);
  }

  EditorFieldPlacement buildTextPlacement(DetectedField field) {
    return EditorFieldPlacement(
      pos: Offset(
        (field.rect.left + field.rect.width + 0.008).clamp(0.0, 0.90).toDouble(),
        (field.rect.top + field.rect.height * 0.1).clamp(0.0, 0.97).toDouble(),
      ),
      size: (field.rect.height * 0.75).clamp(0.014, 0.05).toDouble(),
      title: field.label.replaceAll(':', '').trim(),
    );
  }

  TextInputType keyboardTypeFor(FieldType type) {
    switch (type) {
      case FieldType.number:
      case FieldType.phone:
        return TextInputType.number;
      case FieldType.email:
        return TextInputType.emailAddress;
      default:
        return TextInputType.text;
    }
  }

  String formatDate(DateTime d) {
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  double fitTextSize(String text, double baseSize, double availWidthNorm) {
    if (text.isEmpty) return baseSize;
    const advance = 0.55;
    const pageWH = 1.41;
    final neededH = text.length * advance * baseSize;
    final availH = availWidthNorm * pageWH;
    if (neededH <= availH) return baseSize;
    return (baseSize * (availH / neededH)).clamp(0.010, baseSize).toDouble();
  }

  List<DetectedField> findReplicateTargets(DetectedField source, List<DetectedField> pageFields) {
    final key = _normLabel(source.label);
    if (key.isEmpty) return const [];
    const textLike = {
      FieldType.text,
      FieldType.name,
      FieldType.email,
      FieldType.phone,
      FieldType.number,
      FieldType.date,
    };
    return pageFields
        .where((f) => !identical(f, source) && textLike.contains(f.type) && _normLabel(f.label) == key)
        .toList();
  }

  String cleanLabel(String label) => label.replaceAll(':', '').trim();

  String _normLabel(String s) =>
      s.toLowerCase().replaceAll(':', '').replaceAll(RegExp(r'\s+'), ' ').trim();
}
