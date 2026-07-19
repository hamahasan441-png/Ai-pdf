import 'annotation.dart';

/// Per-page annotation layer with undo + redo history.
class PageLayer {
  final List<EditorAnnotation> items = [];
  final List<EditorAnnotation> redo = [];

  List<StrokeAnnotation> get strokes => items.whereType<StrokeAnnotation>().toList();
  List<ShapeAnnotation> get shapes => items.whereType<ShapeAnnotation>().toList();
  List<TextAnnotation> get texts => items.whereType<TextAnnotation>().toList();
}
