import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Service for managing annotation z-order (layer stacking).
///
/// Controls which annotations render on top of which — essential for
/// professional editing where users need to control the visual stacking.
/// Works directly on the items list (which is draw-order: first = back).
class AnnotationReorderService {
  const AnnotationReorderService();

  /// Move [annotation] to the front (render on top of everything).
  void bringToFront(EditorAnnotation annotation, List<EditorAnnotation> items) {
    if (!items.contains(annotation)) return;
    items.remove(annotation);
    items.add(annotation); // last in list = drawn last = visually on top
  }

  /// Move [annotation] to the back (render behind everything).
  void sendToBack(EditorAnnotation annotation, List<EditorAnnotation> items) {
    if (!items.contains(annotation)) return;
    items.remove(annotation);
    items.insert(0, annotation); // first in list = drawn first = visually behind
  }

  /// Move [annotation] one step forward (one layer up).
  void bringForward(EditorAnnotation annotation, List<EditorAnnotation> items) {
    final index = items.indexOf(annotation);
    if (index < 0 || index >= items.length - 1) return;
    items.removeAt(index);
    items.insert(index + 1, annotation);
  }

  /// Move [annotation] one step backward (one layer down).
  void sendBackward(EditorAnnotation annotation, List<EditorAnnotation> items) {
    final index = items.indexOf(annotation);
    if (index <= 0) return;
    items.removeAt(index);
    items.insert(index - 1, annotation);
  }

  /// Check if [annotation] is already at the front.
  bool isAtFront(EditorAnnotation annotation, List<EditorAnnotation> items) {
    return items.isNotEmpty && items.last == annotation;
  }

  /// Check if [annotation] is already at the back.
  bool isAtBack(EditorAnnotation annotation, List<EditorAnnotation> items) {
    return items.isNotEmpty && items.first == annotation;
  }

  /// Get the current z-index (position in the draw list) of [annotation].
  int zIndexOf(EditorAnnotation annotation, List<EditorAnnotation> items) {
    return items.indexOf(annotation);
  }
}
