import 'package:flutter/material.dart';

import 'package:ai_pdf/core/services/user_profile_service.dart';
import 'package:ai_pdf/features/editor/data/editor_annotation_factory_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_profile_field_picker_sheet.dart';

class EditorProfileInsertService {
  final EditorAnnotationFactoryService _annotationFactory;

  const EditorProfileInsertService({
    EditorAnnotationFactoryService annotationFactory = const EditorAnnotationFactoryService(),
  }) : _annotationFactory = annotationFactory;

  List<ProfileValueOption> buildOptions(Map<String, String> data) {
    return UserProfileService.fields
        .where((f) => (data[f.$1] ?? '').trim().isNotEmpty)
        .map((f) => ProfileValueOption(key: f.$1, label: f.$2, value: data[f.$1]!))
        .toList();
  }

  TextAnnotation buildAnnotation(String value, Color color, double textSize, bool bold) {
    return _annotationFactory.textAt(
      const Offset(0.5, 0.5),
      textSize,
      value,
      color: color,
      bold: bold,
    );
  }
}
