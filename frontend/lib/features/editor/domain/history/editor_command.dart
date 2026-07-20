import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Base class for every undoable/redoable editor command.
///
/// ### Command Pattern
/// Each command captures the minimum state required to:
/// - [execute]  — perform the action on the [PageLayer]
/// - [undo]     — reverse it exactly
///
/// Commands are stored in [HistoryStack] and never hold widget references.
/// They are cheap to keep in memory (no bitmaps, only annotation references
/// + lightweight snapshots of changed fields).
abstract class EditorCommand {
  /// Short description shown in the undo/redo UI tooltip.
  String get description;

  /// Apply (or re-apply) the command.
  void execute(Map<int, PageLayer> layers);

  /// Reverse the command.
  void undo(Map<int, PageLayer> layers);
}

// ---------------------------------------------------------------------------
// Add / Remove
// ---------------------------------------------------------------------------

/// Add one annotation to a page layer.
class AddAnnotationCommand extends EditorCommand {
  final EditorAnnotation annotation;
  final int pageIndex;

  AddAnnotationCommand(this.annotation, this.pageIndex);

  @override
  String get description => 'Add ${annotation.type.name}';

  @override
  void execute(Map<int, PageLayer> layers) {
    _layer(layers).add(annotation);
  }

  @override
  void undo(Map<int, PageLayer> layers) {
    _layer(layers).removeById(annotation.id);
  }

  PageLayer _layer(Map<int, PageLayer> layers) =>
      layers.putIfAbsent(pageIndex, PageLayer.new);
}

/// Remove one annotation from a page layer.
class RemoveAnnotationCommand extends EditorCommand {
  final EditorAnnotation annotation;
  final int pageIndex;
  final int _zIndex;

  RemoveAnnotationCommand(this.annotation, this.pageIndex)
      : _zIndex = annotation.zIndex;

  @override
  String get description => 'Delete ${annotation.type.name}';

  @override
  void execute(Map<int, PageLayer> layers) {
    layers[pageIndex]?.removeById(annotation.id);
  }

  @override
  void undo(Map<int, PageLayer> layers) {
    final layer = layers.putIfAbsent(pageIndex, PageLayer.new);
    annotation.zIndex = _zIndex;
    layer.items.add(annotation);
    // Re-sort so z-order is preserved.
    layer.items.sort((a, b) => a.zIndex.compareTo(b.zIndex));
  }
}

/// Remove multiple annotations (batch delete).
class RemoveMultiCommand extends EditorCommand {
  final List<({EditorAnnotation annotation, int pageIndex, int zIndex})> removed;

  RemoveMultiCommand(List<EditorAnnotation> annotations, int pageIndex)
      : removed = annotations
            .map((a) => (annotation: a, pageIndex: pageIndex, zIndex: a.zIndex))
            .toList();

  @override
  String get description => 'Delete ${removed.length} objects';

  @override
  void execute(Map<int, PageLayer> layers) {
    for (final r in removed) {
      layers[r.pageIndex]?.removeById(r.annotation.id);
    }
  }

  @override
  void undo(Map<int, PageLayer> layers) {
    for (final r in removed) {
      final layer = layers.putIfAbsent(r.pageIndex, PageLayer.new);
      r.annotation.zIndex = r.zIndex;
      layer.items.add(r.annotation);
    }
    for (final layer in layers.values) {
      layer.items.sort((a, b) => a.zIndex.compareTo(b.zIndex));
    }
  }
}

// ---------------------------------------------------------------------------
// Move
// ---------------------------------------------------------------------------

/// Move one annotation by a delta (normalised coords).
class MoveAnnotationCommand extends EditorCommand {
  final String annotationId;
  final int pageIndex;
  final _AnnotationSnapshot _before;
  late final _AnnotationSnapshot _after;
  bool _afterCaptured = false;

  MoveAnnotationCommand(EditorAnnotation annotation, this.pageIndex)
      : annotationId = annotation.id,
        _before = _AnnotationSnapshot.of(annotation);

  /// Call once the drag is complete to record the final position.
  void captureAfter(EditorAnnotation annotation) {
    if (!_afterCaptured) {
      _after = _AnnotationSnapshot.of(annotation);
      _afterCaptured = true;
    }
  }

  @override
  String get description => 'Move';

  @override
  void execute(Map<int, PageLayer> layers) {
    if (!_afterCaptured) return;
    final a = layers[pageIndex]?.findById(annotationId);
    if (a != null) _after.applyTo(a);
  }

  @override
  void undo(Map<int, PageLayer> layers) {
    final a = layers[pageIndex]?.findById(annotationId);
    if (a != null) _before.applyTo(a);
  }
}

// ---------------------------------------------------------------------------
// Edit text
// ---------------------------------------------------------------------------

/// Edit the content or style of a [TextAnnotation].
class EditTextCommand extends EditorCommand {
  final String annotationId;
  final int pageIndex;
  final _TextSnapshot _before;
  final _TextSnapshot _after;

  EditTextCommand({
    required TextAnnotation before,
    required TextAnnotation after,
    required this.pageIndex,
  })  : annotationId = before.id,
        _before = _TextSnapshot.of(before),
        _after = _TextSnapshot.of(after);

  @override
  String get description => 'Edit text';

  @override
  void execute(Map<int, PageLayer> layers) {
    final a = layers[pageIndex]?.findById(annotationId) as TextAnnotation?;
    if (a != null) _after.applyTo(a);
  }

  @override
  void undo(Map<int, PageLayer> layers) {
    final a = layers[pageIndex]?.findById(annotationId) as TextAnnotation?;
    if (a != null) _before.applyTo(a);
  }
}

// ---------------------------------------------------------------------------
// Layer ordering
// ---------------------------------------------------------------------------

class BringToFrontCommand extends EditorCommand {
  final EditorAnnotation annotation;
  final int pageIndex;
  final int _oldZIndex;
  final int _oldPosition;

  BringToFrontCommand(this.annotation, this.pageIndex)
      : _oldZIndex = annotation.zIndex,
        _oldPosition = 0; // set in execute

  @override
  String get description => 'Bring to front';

  @override
  void execute(Map<int, PageLayer> layers) {
    layers[pageIndex]?.bringToFront(annotation);
  }

  @override
  void undo(Map<int, PageLayer> layers) {
    final layer = layers[pageIndex];
    if (layer == null) return;
    layer.remove(annotation);
    annotation.zIndex = _oldZIndex;
    // Re-insert at original position (best effort).
    final pos = (_oldZIndex).clamp(0, layer.items.length);
    layer.items.insert(pos, annotation);
  }
}

// ---------------------------------------------------------------------------
// Internal snapshots (lightweight position/style capture)
// ---------------------------------------------------------------------------

class _AnnotationSnapshot {
  // Common
  final dynamic posOrStart;
  final dynamic endOrNull;
  final List<dynamic>? points;

  _AnnotationSnapshot._(this.posOrStart, this.endOrNull, this.points);

  factory _AnnotationSnapshot.of(EditorAnnotation a) {
    if (a is TextAnnotation) {
      return _AnnotationSnapshot._(a.pos, null, null);
    } else if (a is ShapeAnnotation) {
      return _AnnotationSnapshot._(a.start, a.end, null);
    } else if (a is StrokeAnnotation) {
      return _AnnotationSnapshot._(null, null, List.of(a.points));
    } else if (a is ImageAnnotation) {
      return _AnnotationSnapshot._(a.pos, null, null);
    } else if (a is StampAnnotation) {
      return _AnnotationSnapshot._(a.pos, null, null);
    } else if (a is FormFieldAnnotation) {
      return _AnnotationSnapshot._(a.pos, null, null);
    }
    return _AnnotationSnapshot._(null, null, null);
  }

  void applyTo(EditorAnnotation a) {
    if (a is TextAnnotation && posOrStart != null) a.pos = posOrStart;
    if (a is ShapeAnnotation) {
      if (posOrStart != null) a.start = posOrStart;
      if (endOrNull != null) a.end = endOrNull;
    }
    if (a is StrokeAnnotation && points != null) {
      a.points
        ..clear()
        ..addAll(List<dynamic>.from(points!).cast());
    }
    if (a is ImageAnnotation && posOrStart != null) a.pos = posOrStart;
    if (a is StampAnnotation && posOrStart != null) a.pos = posOrStart;
    if (a is FormFieldAnnotation && posOrStart != null) a.pos = posOrStart;
  }
}

class _TextSnapshot {
  final String text;
  final double size;
  final bool bold, italic, underline;
  final String? fontFamily;
  final dynamic color; // Color

  _TextSnapshot.of(TextAnnotation t)
      : text = t.text,
        size = t.size,
        bold = t.bold,
        italic = t.italic,
        underline = t.underline,
        fontFamily = t.fontFamily,
        color = t.color;

  void applyTo(TextAnnotation t) {
    t.text = text;
    t.size = size;
    t.bold = bold;
    t.italic = italic;
    t.underline = underline;
    t.fontFamily = fontFamily;
    t.color = color;
  }
}
