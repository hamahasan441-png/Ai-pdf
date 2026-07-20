import 'annotation.dart';

/// Per-page annotation layer with undo + redo history.
///
/// [findById] lets controllers and undo commands locate an annotation by its
/// stable [EditorAnnotation.id] instead of relying on object-identity, which
/// breaks after clone / paste operations.
class PageLayer {
  final List<EditorAnnotation> items = [];
  final List<EditorAnnotation> redo = [];

  List<StrokeAnnotation> get strokes =>
      items.whereType<StrokeAnnotation>().toList();
  List<ShapeAnnotation> get shapes =>
      items.whereType<ShapeAnnotation>().toList();
  List<TextAnnotation> get texts =>
      items.whereType<TextAnnotation>().toList();

  /// Returns the first annotation whose [id] matches, or null.
  EditorAnnotation? findById(String id) {
    try {
      return items.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Removes the annotation with the given [id] from [items].
  /// Returns true if an item was removed.
  bool removeById(String id) {
    final index = items.indexWhere((a) => a.id == id);
    if (index < 0) return false;
    redo.add(items.removeAt(index));
    return true;
  }
}
