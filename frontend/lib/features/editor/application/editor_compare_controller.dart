import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_pdf/features/editor/data/document_diff_service.dart';

/// Display mode for the compare view (Phase 30).
enum CompareMode { unified, sideBySide }

/// UI state for the document comparison feature (Phase 30).
class EditorCompareState {
  final bool active;
  final CompareMode mode;
  final String? oldLabel;
  final String? newLabel;
  final List<DiffSegment> lineSegments;
  final DiffStats stats;

  const EditorCompareState({
    this.active = false,
    this.mode = CompareMode.unified,
    this.oldLabel,
    this.newLabel,
    this.lineSegments = const [],
    this.stats = const DiffStats(added: 0, removed: 0, unchanged: 0),
  });
  EditorCompareState copyWith({
    bool? active,
    CompareMode? mode,
    String? oldLabel,
    String? newLabel,
    List<DiffSegment>? lineSegments,
    DiffStats? stats,
  }) =>
      EditorCompareState(
        active: active ?? this.active,
        mode: mode ?? this.mode,
        oldLabel: oldLabel ?? this.oldLabel,
        newLabel: newLabel ?? this.newLabel,
        lineSegments: lineSegments ?? this.lineSegments,
        stats: stats ?? this.stats,
      );
}

class EditorCompareController extends StateNotifier<EditorCompareState> {
  EditorCompareController() : super(const EditorCompareState());

  static const _svc = DocumentDiffService();

  /// Run a diff between [oldText] and [newText].
  void compare(
    String oldText,
    String newText, {
    String? oldLabel,
    String? newLabel,
  }) {
    final segments = _svc.diffLines(oldText, newText);
    final stats = _svc.stats(segments);
    state = state.copyWith(
      active: true,
      lineSegments: segments,
      stats: stats,
      oldLabel: oldLabel,
      newLabel: newLabel,
    );
  }

  void setMode(CompareMode mode) {
    state = state.copyWith(mode: mode);
  }

  void close() {
    state = const EditorCompareState();
  }
}
