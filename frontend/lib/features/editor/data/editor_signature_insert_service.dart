import 'dart:ui' show Offset;

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

class EditorSignatureInsertService {
  const EditorSignatureInsertService();

  StrokeAnnotation signatureFromPadPoints(List<Offset> points) {
    return StrokeAnnotation(
      points.map((p) => Offset(0.1 + p.dx / 900, 0.7 + p.dy / 900)).toList(),
      const Color(0xFF000000),
      2.5,
      false,
    );
  }
}
