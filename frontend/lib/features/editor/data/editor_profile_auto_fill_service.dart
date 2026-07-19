import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/editor_annotation_factory_service.dart';
import 'package:ai_pdf/features/editor/data/editor_field_input_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/detected_field.dart';
import 'package:ai_pdf/features/tools/services/profile_field_matcher.dart';

class EditorAutoFillResult {
  final List<TextAnnotation> annotations;
  final List<DetectedField> remaining;

  const EditorAutoFillResult({
    required this.annotations,
    required this.remaining,
  });

  int get autoCount => annotations.length;
}

/// Auto-fill known profile values into OCR-detected editor fields.
class EditorProfileAutoFillService {
  final EditorFieldInputService _fieldInput;
  final EditorAnnotationFactoryService _annotations;

  const EditorProfileAutoFillService({
    EditorFieldInputService fieldInput = const EditorFieldInputService(),
    EditorAnnotationFactoryService annotations = const EditorAnnotationFactoryService(),
  })  : _fieldInput = fieldInput,
        _annotations = annotations;

  EditorAutoFillResult autoFill({
    required List<DetectedField> fields,
    required Map<String, String> profile,
  }) {
    final annotations = <TextAnnotation>[];
    final remaining = <DetectedField>[];

    for (final field in fields) {
      if (field.type == FieldType.signature) {
        remaining.add(field);
        continue;
      }
      final key = ProfileFieldMatcher.match(field.label);
      final value = key == null ? null : profile[key];
      if (value != null && value.trim().isNotEmpty) {
        final placement = _fieldInput.buildTextPlacement(field);
        annotations.add(
          _annotations.textAt(
            placement.pos,
            (field.rect.height * 0.85).clamp(0.014, 0.06),
            value.trim(),
            color: Colors.black,
          ),
        );
      } else {
        remaining.add(field);
      }
    }

    return EditorAutoFillResult(annotations: annotations, remaining: remaining);
  }
}
