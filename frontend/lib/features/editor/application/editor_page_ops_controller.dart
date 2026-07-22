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

/// Controller for the page operations dialog (Phase 34).
///
/// Parses a human-typed page range (via [PageRangeService], Phase 18) and
/// drives extract / split / delete / rotate / insert-blank operations on the
/// selection. The actual mutation is performed by the screen (using
/// [PageReorderService] for structural ops); this controller owns the UI state
/// and validation.
final editorPageOpsProvider =
    StateNotifierProvider<EditorPageOpsController, EditorPageOpsState>(
        (ref) => EditorPageOpsController());

class EditorPageOpsController extends StateNotifier<EditorPageOpsState> {
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

  /// The inverted (complement) selection — pages NOT in the current range.
  /// Useful for "keep only these pages" = delete the complement.
  List<int> invertedSelection() {
    if (state.parsedIndices == null) return [];
    return _svc.invert(state.parsedIndices!, state.pageCount);
  }

  /// Format the current parsed selection back to a compact spec.
  String formattedSelection() {
    if (state.parsedIndices == null) return '';
    return _svc.format(state.parsedIndices!);
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
