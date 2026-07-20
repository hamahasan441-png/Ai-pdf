import 'editor_command.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Unlimited multi-page undo/redo stack using the Command pattern.
///
/// ### Design
/// - Hard cap at [maxSize] commands to bound memory on long editing sessions.
///   Oldest commands are evicted when the cap is hit (like a circular buffer).
/// - The redo stack is cleared whenever a new command is pushed (standard
///   linear history; no branching).
/// - [isDirty] tracks whether there are unsaved changes — cleared on save.
/// - Thread-safe: all mutations are synchronous Dart, no isolates needed.
class HistoryStack {
  final int maxSize;

  HistoryStack({this.maxSize = 200});

  final List<EditorCommand> _undoStack = [];
  final List<EditorCommand> _redoStack = [];

  bool _dirty = false;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get isDirty => _dirty;

  String? get nextUndoDescription =>
      _undoStack.isNotEmpty ? _undoStack.last.description : null;

  String? get nextRedoDescription =>
      _redoStack.isNotEmpty ? _redoStack.last.description : null;

  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  /// Push and immediately execute a command.
  void push(EditorCommand command, Map<int, PageLayer> layers) {
    command.execute(layers);
    _undoStack.add(command);
    _redoStack.clear();
    _dirty = true;
    // Evict oldest if over capacity.
    if (_undoStack.length > maxSize) {
      _undoStack.removeAt(0);
    }
  }

  /// Undo the most recent command.
  bool undo(Map<int, PageLayer> layers) {
    if (_undoStack.isEmpty) return false;
    final cmd = _undoStack.removeLast();
    cmd.undo(layers);
    _redoStack.add(cmd);
    _dirty = _undoStack.isNotEmpty;
    return true;
  }

  /// Redo the most recently undone command.
  bool redo(Map<int, PageLayer> layers) {
    if (_redoStack.isEmpty) return false;
    final cmd = _redoStack.removeLast();
    cmd.execute(layers);
    _undoStack.add(cmd);
    _dirty = true;
    return true;
  }

  /// Mark the current state as saved (clears dirty flag).
  void markSaved() => _dirty = false;

  /// Clear all history (e.g. on file close).
  void clear() {
    _undoStack.clear();
    _redoStack.clear();
    _dirty = false;
  }
}
