import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single entry in the annotation edit history timeline (Phase 49).
class HistoryTimelineEntry {
  final String id;
  final String label;
  final String? annotationId;
  final int pageIndex;
  final DateTime timestamp;
  final HistoryEntryKind kind;
  final bool isCurrent;

  const HistoryTimelineEntry({
    required this.id,
    required this.label,
    this.annotationId,
    required this.pageIndex,
    required this.timestamp,
    required this.kind,
    this.isCurrent = false,
  });

  HistoryTimelineEntry copyWith({bool? isCurrent}) => HistoryTimelineEntry(
        id: id,
        label: label,
        annotationId: annotationId,
        pageIndex: pageIndex,
        timestamp: timestamp,
        kind: kind,
        isCurrent: isCurrent ?? this.isCurrent,
      );
}

enum HistoryEntryKind { add, delete, move, resize, style, text, batch, reorder }

/// UI state for the annotation history timeline (Phase 49).
class EditorHistoryTimelineState {
  final bool visible;
  final List<HistoryTimelineEntry> entries;
  final int currentIndex;

  const EditorHistoryTimelineState({
    this.visible = false,
    this.entries = const [],
    this.currentIndex = -1,
  });

  bool get hasHistory => entries.isNotEmpty;
  int get totalEntries => entries.length;
  int get undoableCount => currentIndex + 1;
  int get redoableCount => entries.length - currentIndex - 1;

  /// Entries up to and including the current state.
  List<HistoryTimelineEntry> get pastEntries =>
      currentIndex >= 0 ? entries.sublist(0, currentIndex + 1) : const [];

  /// Entries after the current state (redoable future).
  List<HistoryTimelineEntry> get futureEntries =>
      currentIndex < entries.length - 1
          ? entries.sublist(currentIndex + 1)
          : const [];

  EditorHistoryTimelineState copyWith({
    bool? visible,
    List<HistoryTimelineEntry>? entries,
    int? currentIndex,
  }) =>
      EditorHistoryTimelineState(
        visible: visible ?? this.visible,
        entries: entries ?? this.entries,
        currentIndex: currentIndex ?? this.currentIndex,
      );
}

/// Controller for the annotation history timeline panel (Phase 49).
///
/// Visualizes the full edit history as a scrollable timeline — every add,
/// delete, move, style change is a labeled entry with a timestamp. The user
/// can jump to any point in history (non-linear undo), see what was done at
/// each step, and understand the edit flow. Reads from the EditorHistory stack.
final editorHistoryTimelineProvider = StateNotifierProvider<
    EditorHistoryTimelineController,
    EditorHistoryTimelineState>((ref) => EditorHistoryTimelineController());

class EditorHistoryTimelineController
    extends StateNotifier<EditorHistoryTimelineState> {
  EditorHistoryTimelineController()
      : super(const EditorHistoryTimelineState());

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  /// Rebuild the timeline from the command history.
  ///
  /// Called whenever the history stack changes (after undo/redo/new command).
  void rebuild(List<HistoryTimelineEntry> entries, int currentIndex) {
    state = state.copyWith(entries: entries, currentIndex: currentIndex);
  }

  /// Append a new entry (after a new command is executed).
  void pushEntry(HistoryTimelineEntry entry) {
    // Truncate any future entries (redo stack is gone after a new action).
    final newEntries = [
      ...state.entries.sublist(0, state.currentIndex + 1),
      entry,
    ];
    state = state.copyWith(
      entries: newEntries,
      currentIndex: newEntries.length - 1,
    );
  }

  /// Move to a specific history index (time travel).
  void goTo(int index) {
    if (index < 0 || index >= state.entries.length) return;
    state = state.copyWith(currentIndex: index);
  }

  /// Step back one entry (undo).
  void stepBack() {
    if (state.currentIndex > 0) {
      state = state.copyWith(currentIndex: state.currentIndex - 1);
    }
  }

  /// Step forward one entry (redo).
  void stepForward() {
    if (state.currentIndex < state.entries.length - 1) {
      state = state.copyWith(currentIndex: state.currentIndex + 1);
    }
  }

  void clear() => state = const EditorHistoryTimelineState();
}
