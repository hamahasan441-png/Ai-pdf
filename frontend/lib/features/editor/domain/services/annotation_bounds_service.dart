import 'package:flutter/widgets.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Geometry helpers for editor annotations.
///
/// Bounding-box logic now lives on the annotation objects themselves (the
/// unified [EditorAnnotation.bounds] contract). This service is kept as a thin
/// delegator so existing call-sites remain unchanged.
class AnnotationBoundsService {
  const AnnotationBoundsService();

  /// Normalized bounding box of any annotation.
  Rect boundsOf(EditorAnnotation a) => a.bounds;
}
