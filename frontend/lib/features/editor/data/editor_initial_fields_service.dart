import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/signature_placement_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/tools/models/filled_field.dart';

/// Applies AI-/workflow-generated fields to editor layers as editable
/// annotations.
class EditorInitialFieldsService {
  final SignaturePlacementService _signatures;

  const EditorInitialFieldsService({
    SignaturePlacementService signatures = const SignaturePlacementService(),
  }) : _signatures = signatures;

  void applyInitialFields({
    required List<FilledField> fields,
    required int pageCount,
    required Map<int, PageLayer> layers,
    required List<List<Offset>> savedSignatures,
  }) {
    if (fields.isEmpty) return;
    for (final f in fields) {
      final pageIndex = (f.page - 1).clamp(0, (pageCount - 1).clamp(0, 1 << 30));
      final layer = layers.putIfAbsent(pageIndex, () => PageLayer());
      if (f.isSignature && savedSignatures.isNotEmpty) {
        final stroke = _signatures.signatureStrokeAt(savedSignatures.first, f.x, f.y);
        if (stroke != null) {
          layer.items.add(stroke);
          continue;
        }
      }
      final boxSize = f.isCheck ? 0.03 : (f.isSignature ? 0.032 : 0.024);
      layer.items.add(TextAnnotation(
        Offset(f.x, f.y),
        f.text,
        Colors.black,
        boxSize,
        f.isCheck,
        f.isSignature,
        false,
        f.isSignature ? 'serif' : null,
      ));
    }
  }
}
