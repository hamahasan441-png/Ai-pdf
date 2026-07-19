import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_shape_style_dialog.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_text_dialog.dart';

class EditorAnnotationEditService {
  const EditorAnnotationEditService();

  /// Applies a text edit dialog result to [box]. Returns true when a mutation
  /// happened, false when the dialog was cancelled.
  bool applyTextEditResult(
    PageLayer layer,
    TextAnnotation box,
    TextAnnotationEditResult? result, {
    required bool isNew,
    required void Function(TextAnnotation updatedBox) syncDefaults,
  }) {
    if (result == null) return false;
    if (result.isDelete) {
      layer.items.remove(box);
      return true;
    }
    if (result.text.isEmpty) return false;

    box.text = result.text;
    box.color = result.color;
    box.size = result.size;
    box.bold = result.bold;
    box.italic = result.italic;
    box.underline = result.underline;
    box.fontFamily = result.fontFamily;
    syncDefaults(box);
    if (isNew && !layer.items.contains(box)) {
      layer.items.add(box);
      layer.redo.clear();
    }
    return true;
  }

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
