import 'annotation.dart';

/// Per-page annotation layer.
///
/// [items] is the live, ordered list of annotations for this page.
/// [findById] / [removeById] use the stable annotation ID so undo/redo and
/// clipboard operations are safe after clone / paste.
class PageLayer {
  final List<EditorAnnotation> items = [];

  // zIndex management: assign on insert so items paint in creation order.
  int _nextZ = 0;
  int nextZIndex() => _nextZ++;

  // --- Typed accessors ----------------------------------------------------

  List<StrokeAnnotation> get strokes =>
      items.whereType<StrokeAnnotation>().where((a) => a.visible).toList();

  List<ShapeAnnotation> get shapes =>
      items.whereType<ShapeAnnotation>().where((a) => a.visible).toList();

  List<TextAnnotation> get texts =>
      items.whereType<TextAnnotation>().where((a) => a.visible).toList();

  List<ImageAnnotation> get images =>
      items.whereType<ImageAnnotation>().where((a) => a.visible).toList();

  List<StampAnnotation> get stamps =>
      items.whereType<StampAnnotation>().where((a) => a.visible).toList();

  List<FormFieldAnnotation> get formFields =>
      items.whereType<FormFieldAnnotation>().where((a) => a.visible).toList();

  // --- Lookup / mutation ---------------------------------------------------

  /// Returns the first annotation whose [id] matches, or null.
  EditorAnnotation? findById(String id) {
    try {
      return items.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Add an annotation, assigning the next zIndex.
  void add(EditorAnnotation annotation) {
    annotation.zIndex = nextZIndex();
    items.add(annotation);
  }

  /// Remove by id. Returns true if found and removed.
  bool removeById(String id) {
    final index = items.indexWhere((a) => a.id == id);
    if (index < 0) return false;
    items.removeAt(index);
    return true;
  }

  /// Remove a specific instance (by identity).
  bool remove(EditorAnnotation annotation) => items.remove(annotation);

  // --- Layer ordering ------------------------------------------------------

  void bringToFront(EditorAnnotation a) {
    if (!items.contains(a)) return;
    items.remove(a);
    items.add(a);
    a.zIndex = nextZIndex();
  }

  void sendToBack(EditorAnnotation a) {
    if (!items.contains(a)) return;
    items.remove(a);
    items.insert(0, a);
    // Re-normalise zIndex values so back is always 0.
    for (var i = 0; i < items.length; i++) {
      items[i].zIndex = i;
    }
    _nextZ = items.length;
  }

  void bringForward(EditorAnnotation a) {
    final i = items.indexOf(a);
    if (i < 0 || i >= items.length - 1) return;
    items.removeAt(i);
    items.insert(i + 1, a);
  }

  void sendBackward(EditorAnnotation a) {
    final i = items.indexOf(a);
    if (i <= 0) return;
    items.removeAt(i);
    items.insert(i - 1, a);
  }

  // --- Serialisation -------------------------------------------------------

  List<Map<String, dynamic>> toJson() => items.map((a) => a.toJson()).toList();
}
