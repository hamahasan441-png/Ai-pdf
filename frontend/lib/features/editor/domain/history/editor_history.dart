import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'editor_command.dart';

/// Unlimited (bounded) undo/redo stack using the Command pattern.
///
/// ### Design
/// - Each page has its own history (keyed by page index in the owning screen).
/// - [maxDepth] caps memory usage; oldest commands are dropped when exceeded.
/// - Pushing a new command clears the redo stack (standard linear history).
/// - [canUndo] / [canRedo] drive the UI button states.
///
/// ### Thread safety
/// All mutations are synchronous Dart (single-isolate); no locking needed.
class EditorHistory {
  final int maxDepth;

  EditorHistory({this.maxDepth = 200});

  final List<EditorCommand> _undoStack = [];
  final List<EditorCommand> _redoStack = [];

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  /// The label of the next command to undo (for tooltips / history panel).
  String? get nextUndoLabel => _undoStack.isNotEmpty ? _undoStack.last.label : null;
  String? get nextRedoLabel => _redoStack.isNotEmpty ? _redoStack.last.label : null;

  /// Execute a command and push it onto the undo stack.
  void push(EditorCommand command, PageLayer layer) {
    command.execute(layer);
    _undoStack.add(command);
    _redoStack.clear();
    // Evict oldest if over capacity.
    if (_undoStack.length > maxDepth) {
      _undoStack.removeAt(0);
    }
  }

  /// Undo the most recent command.
  bool undo(PageLayer layer) {
    if (_undoStack.isEmpty) return false;
    final cmd = _undoStack.removeLast();
    cmd.undo(layer);
    _redoStack.add(cmd);
    return true;
  }

  /// Redo the most recently undone command.
  bool redo(PageLayer layer) {
    if (_redoStack.isEmpty) return false;
    final cmd = _redoStack.removeLast();
    cmd.execute(layer);
    _undoStack.add(cmd);
    return true;
  }

  /// Clear all history (e.g. on file close / new file).
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}
