import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/editor_annotation_factory_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';

/// Maps tap-based editor tools to the annotations they should create.
class EditorTapToolService {
  final EditorAnnotationFactoryService _annotationFactory;

  const EditorTapToolService({
    EditorAnnotationFactoryService annotationFactory = const EditorAnnotationFactoryService(),
  }) : _annotationFactory = annotationFactory;

  bool isTextTool(EditTool tool) => tool == EditTool.text;

  TextAnnotation buildTextDraft(Offset n, Color color, double textSize, bool bold) {
    return TextAnnotation(n, '', color, textSize, bold);
  }

  TextAnnotation? buildMarkAnnotation(EditTool tool, Offset n) {
    switch (tool) {
      case EditTool.check:
        return _annotationFactory.markAt(n, '✓', const Color(0xFF16A34A));
      case EditTool.cross:
        return _annotationFactory.markAt(n, '✕', const Color(0xFFDC2626));
      case EditTool.dot:
        return _annotationFactory.markAt(n, '●', Colors.black);
      case EditTool.dash:
        return _annotationFactory.markAt(n, '—', Colors.black);
      case EditTool.checkbox:
        return _annotationFactory.markAt(n, '☑', Colors.black);
      default:
        return null;
    }
  }
}
