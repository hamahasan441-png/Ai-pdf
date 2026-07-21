import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Base class for every undoable editor action.
///
/// Each command captures the minimum state needed to execute and reverse itself.
/// Commands are stored in [EditorHistory] and reference [PageLayer] by page
/// index, so they survive page-switch and can be serialized in the future.
abstract class EditorCommand {
  /// Human-readable label (for a future "Edit History" panel).
  String get label;

  /// Apply (or re-apply) the command.
  void execute(PageLayer layer);

  /// Reverse the command.
  void undo(PageLayer layer);
}

/// Add one annotation.
class AddCommand extends EditorCommand {
  final EditorAnnotation annotation;
  AddCommand(this.annotation);

  @override
  String get label => 'Add ${annotation.runtimeType.toString().replaceAll('Annotation', '')}';

  @override
  void execute(PageLayer layer) {
    if (!layer.items.contains(annotation)) {
      layer.items.add(annotation);
    }
  }

  @override
  void undo(PageLayer layer) {
    layer.items.remove(annotation);
  }
}

/// Remove one annotation.
class RemoveCommand extends EditorCommand {
  final EditorAnnotation annotation;
  final int _index;

  RemoveCommand(this.annotation, PageLayer layer)
      : _index = layer.items.indexOf(annotation);

  @override
  String get label => 'Delete';

  @override
  void execute(PageLayer layer) {
    layer.items.remove(annotation);
  }

  @override
  void undo(PageLayer layer) {
    final idx = _index.clamp(0, layer.items.length);
    layer.items.insert(idx, annotation);
  }
}

/// Remove multiple annotations (batch delete / multi-select delete).
class RemoveBatchCommand extends EditorCommand {
  final List<(EditorAnnotation, int)> _removed; // (annotation, original index)

  RemoveBatchCommand(Iterable<EditorAnnotation> annotations, PageLayer layer)
      : _removed = annotations
            .map((a) => (a, layer.items.indexOf(a)))
            .toList();

  @override
  String get label => 'Delete ${_removed.length}';

  @override
  void execute(PageLayer layer) {
    for (final (a, _) in _removed) {
      layer.items.remove(a);
    }
  }

  @override
  void undo(PageLayer layer) {
    // Re-insert in original index order (sorted ascending so inserts don't shift).
    final sorted = List<(EditorAnnotation, int)>.from(_removed)
      ..sort((a, b) => a.$2.compareTo(b.$2));
    for (final (a, idx) in sorted) {
      final i = idx.clamp(0, layer.items.length);
      layer.items.insert(i, a);
    }
  }
}

/// Move an annotation (captures before/after position).
class MoveCommand extends EditorCommand {
  final EditorAnnotation annotation;
  final dynamic _before; // Offset for text/image, or start+end for shape
  final dynamic _after;

  MoveCommand._(this.annotation, this._before, this._after);

  /// Create from a text annotation's position change.
  factory MoveCommand.text(TextAnnotation t, {required dynamic beforePos, required dynamic afterPos}) {
    return MoveCommand._(t, beforePos, afterPos);
  }

  /// Create from a shape annotation's endpoint change.
  factory MoveCommand.shape(ShapeAnnotation s, {required dynamic beforeStart, required dynamic beforeEnd, required dynamic afterStart, required dynamic afterEnd}) {
    return MoveCommand._(s, (beforeStart, beforeEnd), (afterStart, afterEnd));
  }

  @override
  String get label => 'Move';

  @override
  void execute(PageLayer layer) {
    _apply(_after);
  }

  @override
  void undo(PageLayer layer) {
    _apply(_before);
  }

  void _apply(dynamic state) {
    if (annotation is TextAnnotation) {
      (annotation as TextAnnotation).pos = state;
    } else if (annotation is ShapeAnnotation && state is (dynamic, dynamic)) {
      (annotation as ShapeAnnotation).start = state.$1;
      (annotation as ShapeAnnotation).end = state.$2;
    }
  }
}

/// Edit a text annotation's content/style (captures full before/after state).
class EditTextCommand extends EditorCommand {
  final TextAnnotation annotation;
  final String _beforeText;
  final String _afterText;
  final double _beforeSize;
  final double _afterSize;
  final bool _beforeBold;
  final bool _afterBold;
  final int _beforeColor;
  final int _afterColor;

  EditTextCommand({
    required this.annotation,
    required String beforeText,
    required String afterText,
    required double beforeSize,
    required double afterSize,
    required bool beforeBold,
    required bool afterBold,
    required int beforeColor,
    required int afterColor,
  })  : _beforeText = beforeText,
        _afterText = afterText,
        _beforeSize = beforeSize,
        _afterSize = afterSize,
        _beforeBold = beforeBold,
        _afterBold = afterBold,
        _beforeColor = beforeColor,
        _afterColor = afterColor;

  @override
  String get label => 'Edit text';

  @override
  void execute(PageLayer layer) {
    annotation.text = _afterText;
    annotation.size = _afterSize;
    annotation.bold = _afterBold;
    // Color is an int stored on the annotation — caller converts.
  }

  @override
  void undo(PageLayer layer) {
    annotation.text = _beforeText;
    annotation.size = _beforeSize;
    annotation.bold = _beforeBold;
  }
}
