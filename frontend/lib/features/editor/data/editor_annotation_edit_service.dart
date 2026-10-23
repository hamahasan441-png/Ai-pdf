import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_shape_style_dialog.dart';

class EditorAnnotationEditService {
  const EditorAnnotationEditService();

  /// Applies a shape style dialog result. Returns true when a mutation happened.
  bool applyShapeStyleResult(ShapeAnnotation shape, ShapeStyleResult? result) {
    if (result == null) return false;
    shape.filled = result.filled;
    shape.opacity = result.opacity;
    shape.width = result.width;
    shape.color = result.color;
    return true;
  }
}
