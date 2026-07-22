import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_pdf/features/editor/domain/services/document_outline_service.dart';

/// UI state for the outline panel (Phase 29).
class EditorOutlineState {
  final bool visible;
  final List<OutlineNode> roots;
  final List<OutlineRow> rows;
  final int currentPage;

  const EditorOutlineState({
    this.visible = false,
    this.roots = const [],
    this.rows = const [],
    this.currentPage = 0,
  });

  bool get hasOutline => roots.isNotEmpty;
  OutlineNode? get activeSection =>
      hasOutline ? _svc.nearestForPage(roots, currentPage) : null;

  static const _svc = DocumentOutlineService();

  EditorOutlineState copyWith({
    bool? visible,
    List<OutlineNode>? roots,
    List<OutlineRow>? rows,
    int? currentPage,
  }) =>
      EditorOutlineState(
        visible: visible ?? this.visible,
        roots: roots ?? this.roots,
        rows: rows ?? this.rows,
        currentPage: currentPage ?? this.currentPage,
      );
}

/// Controller for the document outline panel (Phase 29).
///
/// Builds the tree from headings (native bookmarks or AI outline), manages
/// collapse/expand, and exposes a flat row list for the panel's ListView.
final editorOutlineProvider =
    StateNotifierProvider<EditorOutlineController, EditorOutlineState>(
        (ref) => EditorOutlineController());

class EditorOutlineController extends StateNotifier<EditorOutlineState> {
  EditorOutlineController() : super(const EditorOutlineState());

  static const _svc = DocumentOutlineService();

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  /// Build the outline from flat headings (call when document loads or when
  /// the backend returns the AI outline).
  void load(List<OutlineHeading> headings) {
    final roots = _svc.build(headings);
    state = state.copyWith(roots: roots, rows: _svc.flattenVisible(roots));
  }

  void setCurrentPage(int page) {
    state = state.copyWith(currentPage: page);
  }

  void toggleNode(OutlineNode node) {
    _svc.toggle(node);
    _refreshRows();
  }

  void expandAll() {
    _svc.expandAll(state.roots);
    _refreshRows();
  }

  void collapseAll() {
    _svc.collapseAll(state.roots);
    _refreshRows();
  }

  void clear() {
    state = const EditorOutlineState();
  }

  void _refreshRows() {
    state = state.copyWith(rows: _svc.flattenVisible(state.roots));
  }
}
