import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_pdf/features/editor/domain/services/page_range_service.dart';

/// What kind of page operation the user is requesting (Phase 34).
enum PageOperation { extract, split, delete, rotateLeft, rotateRight, insertBlank }

/// UI state for the page operations dialog (Phase 34).
class EditorPageOpsState {
  final bool visible;
  final String rangeSpec;
  final List<int>? parsedIndices;
  final String? parseError;
  final int pageCount;
  final PageOperation operation;

  const EditorPageOpsState({
    this.visible = false,
    this.rangeSpec = '',
    this.parsedIndices,
    this.parseError,
    this.pageCount = 1,
    this.operation = PageOperation.extract,
  });

  bool get isValid => parsedIndices != null && parsedIndices!.isNotEmpty;
  int get selectedCount => parsedIndices?.length ?? 0;

  EditorPageOpsState copyWith({
    bool? visible,
    String? rangeSpec,
    List<int>? parsedIndices,
    String? parseError,
    int? pageCount,
    PageOperation? operation,
    bool clearError = false,
  }) =>
      EditorPageOpsState(
        visible: visible ?? this.visible,
        rangeSpec: rangeSpec ?? this.rangeSpec,
        parsedIndices: parsedIndices ?? this.parsedIndices,
        parseError: clearError ? null : (parseError ?? this.parseError),
        pageCount: pageCount ?? this.pageCount,
        operation: operation ?? this.operation,
      );
}

class EditorPageOpsController extends StateNotifier<EditorPageOpsState> {
  /// The current state, for widgets that own this controller directly
  /// (StateNotifier keeps [state] protected).
  EditorPageOpsState get current => state;

  EditorPageOpsController() : super(const EditorPageOpsState());

  static const _svc = PageRangeService();

  void show({required int pageCount}) {
    state = EditorPageOpsState(visible: true, pageCount: pageCount);
  }

  void hide() => state = const EditorPageOpsState();

  void setOperation(PageOperation op) {
    state = state.copyWith(operation: op);
  }

  void setPageCount(int count) {
    state = state.copyWith(pageCount: count);
    _reparse();
  }

  /// Called on every keystroke in the range text field.
  void setRangeSpec(String spec) {
    state = state.copyWith(rangeSpec: spec, clearError: true);
    _reparse();
  }

  /// Convenience: set range to "all pages".
  void selectAll() {
    final spec = '1-${state.pageCount}';
    state = state.copyWith(rangeSpec: spec, clearError: true);
    _reparse();
  }

  /// Convenience: set range to current page only.
  void selectCurrent(int currentPage) {
    final spec = '${currentPage + 1}';
    state = state.copyWith(rangeSpec: spec, clearError: true);
    _reparse();
  }

  void _reparse() {
    final result = _svc.tryParse(state.rangeSpec, state.pageCount);
    if (result == null && state.rangeSpec.trim().isNotEmpty) {
      state = state.copyWith(
        parsedIndices: null,
        parseError: 'Invalid range',
      );
    } else {
      state = state.copyWith(
        parsedIndices: result ?? const [],
        clearError: true,
      );
    }
  }
}
