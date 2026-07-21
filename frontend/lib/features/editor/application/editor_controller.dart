import 'dart:ui' show Offset, Rect;

import 'package:flutter/widgets.dart' show Axis;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/history/editor_command.dart';
import 'package:ai_pdf/features/editor/domain/history/editor_history.dart';
import 'package:ai_pdf/features/editor/domain/services/annotation_bounds_service.dart';
import 'package:ai_pdf/features/editor/domain/services/selection_service.dart';

import 'editor_state.dart';

final editorControllerProvider =
    StateNotifierProvider<EditorController, EditorState>((ref) {
  return EditorController();
});

/// Editor controller with Command-pattern undo/redo.
///
/// Internally uses [EditorHistory] for unlimited, object-level undo/redo.
/// The public API is unchanged from the previous flat implementation so
/// pick_edit_screen.dart requires zero modifications.
class EditorController extends StateNotifier<EditorState> {
  EditorController() : super(const EditorState());

  /// Per-page history stacks. Keyed by page index.
  final Map<int, EditorHistory> _histories = {};

  /// Get or create the history for a given page.
  EditorHistory _historyFor(int page) =>
      _histories.putIfAbsent(page, () => EditorHistory());

  /// Current page's history.
  EditorHistory get _currentHistory => _historyFor(state.currentPage);

  // ─── Lifecycle ──────────────────────────────────────────────────────────

  void setLoading(bool value) {
    state = state.copyWith(loading: value);
  }

  void setExporting(bool value) {
    state = state.copyWith(exporting: value);
  }

  void setPage({required int currentPage, required int pageCount}) {
    state = state.copyWith(currentPage: currentPage, pageCount: pageCount);
  }

  void setCurrentPage(int currentPage) {
    state = state.copyWith(currentPage: currentPage);
  }

  void setPageCount(int pageCount) {
    state = state.copyWith(pageCount: pageCount);
  }

  void setFile({String? filePath, String? fileName}) {
    state = state.copyWith(filePath: filePath, fileName: fileName);
  }

  void setUnsavedChanges(bool value) {
    state = state.copyWith(hasUnsavedChanges: value);
  }

  void setError(String? message) {
    state = state.copyWith(error: message);
  }

  void beginOpenFile({required String fileName, String? filePath}) {
    _histories.clear();
    state = EditorState(
      loading: true,
      exporting: false,
      currentPage: 0,
      pageCount: 0,
      hasUnsavedChanges: false,
      filePath: filePath,
      fileName: fileName,
      error: null,
    );
  }

  void finishOpenFile({required int pageCount, int currentPage = 0}) {
    state = state.copyWith(
      loading: false,
      currentPage: currentPage,
      pageCount: pageCount,
      error: null,
    );
  }

  void failOpenFile(String error) {
    state = state.copyWith(loading: false, error: error);
  }

  void beginPageChange() {
    state = state.copyWith(loading: true);
  }

  void finishPageChange(int currentPage) {
    state = state.copyWith(loading: false, currentPage: currentPage);
  }

  void beginExport() {
    state = state.copyWith(loading: true, exporting: true, error: null);
  }

  void finishExport({String? error}) {
    state = state.copyWith(loading: false, exporting: false, error: error);
  }

  void markDirty() {
    state = state.copyWith(hasUnsavedChanges: true);
  }

  void clearDirty() {
    state = state.copyWith(hasUnsavedChanges: false);
  }

  // ─── Undo / Redo (now backed by EditorHistory) ──────────────────────────

  void undo(PageLayer layer) {
    if (_currentHistory.undo(layer)) {
      markDirty();
    }
  }

  void redo(PageLayer layer) {
    if (_currentHistory.redo(layer)) {
      markDirty();
    }
  }

  bool eraseLast(PageLayer layer) {
    if (layer.items.isEmpty) return false;
    final removed = layer.items.last;
    _currentHistory.push(RemoveCommand(removed, layer), layer);
    markDirty();
    return true;
  }

  // ─── Annotation mutations (all go through history) ──────────────────────

  void pushAnnotation(PageLayer layer, EditorAnnotation annotation) {
    _currentHistory.push(AddCommand(annotation), layer);
    markDirty();
  }

  EditorAnnotation? deleteSelected(PageLayer layer, EditorAnnotation? selected) {
    if (selected == null) return selected;
    _currentHistory.push(RemoveCommand(selected, layer), layer);
    markDirty();
    return null;
  }

  void deleteMulti(PageLayer layer, Iterable<EditorAnnotation> selected) {
    _currentHistory.push(RemoveBatchCommand(selected, layer), layer);
    markDirty();
  }

  // ─── Selection / move / resize (unchanged API) ──────────────────────────

  SelectionSnapGuides? moveSelected(
    EditorAnnotation? selected,
    Offset deltaNorm,
    SelectionService selection,
    AnnotationBoundsService bounds,
  ) {
    if (selected == null) return null;
    selection.moveSelected(selected, deltaNorm);
    markDirty();
    return selection.snapSelected(selected, bounds);
  }

  SelectionSnapGuides? scaleSelectedTo(
    EditorAnnotation? selected,
    Rect nextBounds,
    SelectionService selection,
    AnnotationBoundsService bounds,
  ) {
    if (selected == null) return null;
    selection.scaleSelectedTo(selected, nextBounds, bounds);
    markDirty();
    return selection.snapSelected(selected, bounds);
  }

  bool resizeSelectedShape(
    EditorAnnotation? selected,
    Offset newEndNorm,
    SelectionService selection,
  ) {
    final changed = selected != null && selection.resizeSelectedShape(selected, newEndNorm);
    if (changed) markDirty();
    return changed;
  }

  bool resizeSelectedText(
    EditorAnnotation? selected,
    double factor,
    SelectionService selection,
  ) {
    final changed = selected != null && selection.resizeSelectedText(selected, factor);
    if (changed) markDirty();
    return changed;
  }

  void moveAnnotation(EditorAnnotation annotation, Offset d, SelectionService selection) {
    selection.moveAnnotation(annotation, d);
    markDirty();
  }

  void alignMulti(
    Set<EditorAnnotation> selectionSet,
    String how,
    SelectionService selection,
    AnnotationBoundsService bounds,
  ) {
    selection.alignAnnotations(selectionSet, how, bounds);
    markDirty();
  }

  void distributeMulti(
    List<EditorAnnotation> selectionSet,
    Axis axis,
    SelectionService selection,
    AnnotationBoundsService bounds,
  ) {
    selection.distributeAnnotations(selectionSet, axis, bounds);
    markDirty();
  }

  // ─── Clipboard / duplicate / reorder (unchanged API) ────────────────────

  EditorAnnotation? copySelected(
    EditorAnnotation? selected,
    SelectionService selection,
  ) {
    if (selected == null) return null;
    return selection.cloneAnnotation(selected, 0);
  }

  EditorAnnotation? pasteClipboard(
    PageLayer layer,
    EditorAnnotation? clipboard,
    SelectionService selection,
  ) {
    if (clipboard == null) return null;
    final copy = selection.cloneAnnotation(clipboard, 0.03);
    if (copy != null) {
      _currentHistory.push(AddCommand(copy), layer);
      markDirty();
    }
    return copy;
  }

  EditorAnnotation? duplicateSelected(
    PageLayer layer,
    EditorAnnotation? selected,
    SelectionService selection,
  ) {
    if (selected == null) return null;
    final copy = selection.cloneAnnotation(selected, 0.03);
    if (copy != null) {
      _currentHistory.push(AddCommand(copy), layer);
      markDirty();
    }
    return copy;
  }

  List<EditorAnnotation> duplicateMulti(
    PageLayer layer,
    Iterable<EditorAnnotation> selected,
    SelectionService selection,
  ) {
    final copies = <EditorAnnotation>[];
    for (final item in selected) {
      final copy = selection.cloneAnnotation(item, 0.03);
      if (copy != null) copies.add(copy);
    }
    for (final copy in copies) {
      _currentHistory.push(AddCommand(copy), layer);
    }
    if (copies.isNotEmpty) markDirty();
    return copies;
  }

  void bringToFront(
    PageLayer layer,
    EditorAnnotation? selected,
    SelectionService selection,
  ) {
    if (selected == null) return;
    selection.bringToFront(selected, layer.items);
    markDirty();
  }

  void sendToBack(
    PageLayer layer,
    EditorAnnotation? selected,
    SelectionService selection,
  ) {
    if (selected == null) return;
    selection.sendToBack(selected, layer.items);
    markDirty();
  }
}
