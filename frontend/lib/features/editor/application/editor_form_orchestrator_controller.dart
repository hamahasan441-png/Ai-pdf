import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A detected form field ready for orchestrated fill (Phase 36).
class OrchestratedField {
  final String id;
  final int pageIndex;
  final String label;
  final String fieldType;
  final String? currentValue;
  final bool filled;
  final bool skipped;

  const OrchestratedField({
    required this.id,
    required this.pageIndex,
    required this.label,
    required this.fieldType,
    this.currentValue,
    this.filled = false,
    this.skipped = false,
  });

  bool get pending => !filled && !skipped;

  OrchestratedField copyWith({
    String? currentValue,
    bool? filled,
    bool? skipped,
  }) =>
      OrchestratedField(
        id: id,
        pageIndex: pageIndex,
        label: label,
        fieldType: fieldType,
        currentValue: currentValue ?? this.currentValue,
        filled: filled ?? this.filled,
        skipped: skipped ?? this.skipped,
      );
}

/// UI state for the multi-page form fill orchestrator (Phase 36).
class EditorFormOrchestratorState {
  final bool active;
  final List<OrchestratedField> fields;
  final int currentIndex;
  final bool autoAdvance;

  const EditorFormOrchestratorState({
    this.active = false,
    this.fields = const [],
    this.currentIndex = 0,
    this.autoAdvance = true,
  });

  int get total => fields.length;
  int get filledCount => fields.where((f) => f.filled).length;
  int get skippedCount => fields.where((f) => f.skipped).length;
  int get pendingCount => fields.where((f) => f.pending).length;
  double get progress => total == 0 ? 0 : (filledCount + skippedCount) / total;
  bool get isComplete => pendingCount == 0;
  OrchestratedField? get currentField =>
      currentIndex >= 0 && currentIndex < fields.length
          ? fields[currentIndex]
          : null;

  /// The page the current field lives on.
  int get currentPage => currentField?.pageIndex ?? 0;

  EditorFormOrchestratorState copyWith({
    bool? active,
    List<OrchestratedField>? fields,
    int? currentIndex,
    bool? autoAdvance,
  }) =>
      EditorFormOrchestratorState(
        active: active ?? this.active,
        fields: fields ?? this.fields,
        currentIndex: currentIndex ?? this.currentIndex,
        autoAdvance: autoAdvance ?? this.autoAdvance,
      );
}

/// Controller for the multi-page form fill orchestrator (Phase 36).
///
/// Walks the user through ALL form fields across ALL pages of the document in a
/// guided flow. Fields are sorted by page then position so the user fills top→
/// bottom, page by page, with auto-advance to the next unfilled field. Progress
/// bar, skip, and "fill remaining with AI" actions supported.
final editorFormOrchestratorProvider = StateNotifierProvider<
    EditorFormOrchestratorController,
    EditorFormOrchestratorState>((ref) => EditorFormOrchestratorController());

class EditorFormOrchestratorController
    extends StateNotifier<EditorFormOrchestratorState> {
  EditorFormOrchestratorController()
      : super(const EditorFormOrchestratorState());

  void start(List<OrchestratedField> fields) {
    state = state.copyWith(active: true, fields: fields, currentIndex: 0);
  }

  void stop() => state = const EditorFormOrchestratorState();

  /// Mark the current field as filled and advance.
  void fillCurrent(String value) {
    _updateCurrent((f) => f.copyWith(currentValue: value, filled: true));
    if (state.autoAdvance) _advanceToNextPending();
  }

  /// Skip the current field and advance.
  void skipCurrent() {
    _updateCurrent((f) => f.copyWith(skipped: true));
    if (state.autoAdvance) _advanceToNextPending();
  }

  /// Go to a specific field by index.
  void goTo(int index) {
    if (index >= 0 && index < state.fields.length) {
      state = state.copyWith(currentIndex: index);
    }
  }

  /// Jump to the next pending field (wraps around once).
  void next() => _advanceToNextPending();

  /// Jump to the previous pending field.
  void previous() {
    for (var i = state.currentIndex - 1; i >= 0; i--) {
      if (state.fields[i].pending) {
        state = state.copyWith(currentIndex: i);
        return;
      }
    }
  }

  void setAutoAdvance(bool value) =>
      state = state.copyWith(autoAdvance: value);

  void _updateCurrent(OrchestratedField Function(OrchestratedField) transform) {
    final idx = state.currentIndex;
    if (idx < 0 || idx >= state.fields.length) return;
    state = state.copyWith(
      fields: [
        for (var i = 0; i < state.fields.length; i++)
          if (i == idx) transform(state.fields[i]) else state.fields[i],
      ],
    );
  }

  void _advanceToNextPending() {
    for (var i = state.currentIndex + 1; i < state.fields.length; i++) {
      if (state.fields[i].pending) {
        state = state.copyWith(currentIndex: i);
        return;
      }
    }
    // Wrap once from the start.
    for (var i = 0; i < state.currentIndex; i++) {
      if (state.fields[i].pending) {
        state = state.copyWith(currentIndex: i);
        return;
      }
    }
    // All done.
  }
}
