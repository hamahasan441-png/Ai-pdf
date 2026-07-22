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

/// Restore the mutable state of one or more annotations to a captured
/// before/after snapshot.
///
/// This is the generic command that makes *every* in-place edit undoable —
/// move, resize/scale, alignment, distribution, colour, style, font size, and
/// inline text changes — regardless of the object type. It works by asking each
/// live annotation to [EditorAnnotation.restoreFrom] a detached memento of its
/// own runtime type, so existing references (selection, inline editor) stay
/// valid after undo/redo.
///
/// The [targets] are the live objects in the layer; [_before] and [_after] are
/// same-index memento snapshots produced via `target.clone(id: target.id)`.
/// The edit is applied *live* before the command is pushed, so [execute]
/// (used for redo) simply re-applies the already-current after-state and is a
/// no-op on first push.
class RestoreStateCommand extends EditorCommand {
  final List<EditorAnnotation> _targets;
  final List<EditorAnnotation> _before;
  final List<EditorAnnotation> _after;
  final String _label;

  RestoreStateCommand(
    List<EditorAnnotation> targets,
    List<EditorAnnotation> before,
    List<EditorAnnotation> after, [
    this._label = 'Edit',
  ])  : _targets = List<EditorAnnotation>.of(targets),
        _before = List<EditorAnnotation>.of(before),
        _after = List<EditorAnnotation>.of(after);

  @override
  String get label => _label;

  @override
  void execute(PageLayer layer) {
    for (var i = 0; i < _targets.length; i++) {
      _targets[i].restoreFrom(_after[i]);
    }
  }

  @override
  void undo(PageLayer layer) {
    for (var i = 0; i < _targets.length; i++) {
      _targets[i].restoreFrom(_before[i]);
    }
  }
}

/// Restore the paint order of a layer to a captured before/after snapshot.
///
/// Used by bring-to-front / send-to-back (and any future grouping / reorder
/// operation). Captures the full [PageLayer.items] ordering so it is robust for
/// single- and multi-object reordering alike.
class ReorderCommand extends EditorCommand {
  final List<EditorAnnotation> _before;
  final List<EditorAnnotation> _after;
  final String _label;

  ReorderCommand(
    List<EditorAnnotation> before,
    List<EditorAnnotation> after, [
    this._label = 'Reorder',
  ])  : _before = List<EditorAnnotation>.of(before),
        _after = List<EditorAnnotation>.of(after);

  @override
  String get label => _label;

  @override
  void execute(PageLayer layer) {
    layer.items
      ..clear()
      ..addAll(_after);
  }

  @override
  void undo(PageLayer layer) {
    layer.items
      ..clear()
      ..addAll(_before);
  }
}
