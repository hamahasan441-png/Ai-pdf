import 'dart:ui' show Offset, Rect;

import 'package:flutter/widgets.dart' show Axis, TextAlign, TextDirection;
import 'package:flutter/material.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/history/editor_command.dart';
import 'package:ai_pdf/features/editor/domain/history/history_stack.dart';
import 'package:ai_pdf/features/editor/domain/services/annotation_bounds_service.dart';
import 'package:ai_pdf/features/editor/domain/services/selection_service.dart';

import 'editor_state.dart';

final editorControllerProvider =
    StateNotifierProvider<EditorController, EditorState>((ref) {
  return EditorController();
});

/// Central editor ViewModel.
///
/// ### Responsibilities
/// - Owns [_layers] (one [PageLayer] per page)
/// - Owns [_history] (unlimited undo/redo via Command pattern)
/// - Exposes [EditorState] (immutable snapshot consumed by widgets)
/// - Dispatches commands to [_history] so every mutation is undoable
///
/// ### What it does NOT do
/// - UI logic (dialogs, sheets) — that stays in the screen
/// - File I/O — delegated to data-layer services called by the screen
/// - Rendering — delegated to [EditorCanvasPainter]
class EditorController extends StateNotifier<EditorState> {
  EditorController() : super(const EditorState());

  // ── Page layers ──────────────────────────────────────────────────────────
  /// All annotations, keyed by 0-based page index.
  final Map<int, PageLayer> _layers = {};

  /// Read-only access for the renderer.
  Map<int, PageLayer> get layers => Map.unmodifiable(_layers);

  PageLayer layerFor(int page) => _layers.putIfAbsent(page, PageLayer.new);

  // ── History ──────────────────────────────────────────────────────────────
  final HistoryStack _history = HistoryStack(maxSize: 300);

  bool get canUndo => _history.canUndo;
  bool get canRedo => _history.canRedo;

  // ── Services ─────────────────────────────────────────────────────────────
  final AnnotationBoundsService _bounds = const AnnotationBoundsService();
  final SelectionService _selection = const SelectionService();

  // ── Selected annotation (fast lookup) ────────────────────────────────────
  EditorAnnotation? get selected {
    final id = state.selectedId;
    if (id == null) return null;
    return _layers[state.currentPage]?.findById(id);
  }

  Set<EditorAnnotation> get multiSelected {
    if (state.multiIds.isEmpty) return const {};
    final layer = _layers[state.currentPage];
    if (layer == null) return const {};
    return state.multiIds
        .map((id) => layer.findById(id))
        .whereType<EditorAnnotation>()
        .toSet();
  }

  // =========================================================================
  // Document lifecycle
  // =========================================================================

  void beginOpenFile({required String fileName, String? filePath}) {
    _layers.clear();
    _history.clear();
    state = EditorState(
      loading: true,
      fileName: fileName,
      filePath: filePath,
    );
  }

  void finishOpenFile({required int pageCount, int currentPage = 0}) {
    state = state.copyWith(
      loading: false,
      pageCount: pageCount,
      currentPage: currentPage,
      clearError: true,
      canUndo: false,
      canRedo: false,
    );
  }

  void failOpenFile(String error) {
    state = state.copyWith(loading: false, error: error);
  }

  void setCurrentPage(int page) {
    state = state.copyWith(currentPage: page, clearSelection: true);
    _syncHistory();
  }

  void beginExport() {
    state = state.copyWith(loading: true, exporting: true, clearError: true);
  }

  void finishExport({String? error}) {
    _history.markSaved();
    state = state.copyWith(
      loading: false,
      exporting: false,
      error: error,
      hasUnsavedChanges: false,
      canUndo: _history.canUndo,
      canRedo: _history.canRedo,
    );
  }

  void setError(String? message) {
    state = message == null
        ? state.copyWith(clearError: true)
        : state.copyWith(error: message);
  }

  // =========================================================================
  // Tool + style
  // =========================================================================

  void setTool(EditTool tool) {
    state = state.copyWith(tool: tool, clearSelection: true);
  }

  void setPenColor(Color color) => state = state.copyWith(penColor: color);
  void setPenStroke(double stroke) => state = state.copyWith(penStroke: stroke);
  void setTextSize(double pt) => state = state.copyWith(textSize: pt);
  void setTextBold(bool v) => state = state.copyWith(textBold: v);
  void setTextItalic(bool v) => state = state.copyWith(textItalic: v);
  void setTextUnderline(bool v) => state = state.copyWith(textUnderline: v);
  void setTextFontFamily(String? family) =>
      family == null ? state = state.copyWith(clearTextFont: true) : state = state.copyWith(textFontFamily: family);
  void setTextAlign(TextAlign align) => state = state.copyWith(textAlign: align);
  void setTextDirection(TextDirection? dir) =>
      dir == null
          ? state = state.copyWith(clearTextDirection: true)
          : state = state.copyWith(textDirection: dir);
  void setTextLineHeight(double lh) => state = state.copyWith(textLineHeight: lh);
  void setZoom(double zoom) => state = state.copyWith(zoom: zoom.clamp(0.5, 8.0));

  // =========================================================================
  // Selection
  // =========================================================================

  void select(EditorAnnotation? annotation) {
    state = state.copyWith(
      selectedId: annotation?.id,
      multiIds: const {},
      clearSelection: annotation == null,
    );
  }

  void deselect() {
    state = state.copyWith(clearSelection: true, multiIds: const {}, clearGuideX: true, clearGuideY: true);
  }

  void setMultiSelection(Set<EditorAnnotation> annotations) {
    state = state.copyWith(
      multiIds: annotations.map((a) => a.id).toSet(),
      clearSelection: true,
    );
  }

  void setSnapGuides(SelectionSnapGuides? guides) {
    if (guides == null) {
      state = state.copyWith(clearGuideX: true, clearGuideY: true);
    } else {
      state = guides.guideX != null
          ? state.copyWith(guideX: guides.guideX, clearGuideY: guides.guideY == null)
          : state.copyWith(clearGuideX: true);
      state = guides.guideY != null
          ? state.copyWith(guideY: guides.guideY)
          : state.copyWith(clearGuideY: true);
    }
  }

  // =========================================================================
  // Annotation commands (all go through HistoryStack)
  // =========================================================================

  void addAnnotation(EditorAnnotation annotation) {
    annotation.pageIndex = state.currentPage;
    _history.push(AddAnnotationCommand(annotation, state.currentPage), _layers);
    _syncHistory();
  }

  void deleteSelected() {
    final sel = selected;
    if (sel == null || sel.locked) return;
    final page = state.currentPage;
    _history.push(RemoveAnnotationCommand(sel, page), _layers);
    state = state.copyWith(clearSelection: true, clearGuideX: true, clearGuideY: true);
    _syncHistory();
  }

  void deleteMulti() {
    final multi = multiSelected;
    if (multi.isEmpty) return;
    _history.push(RemoveMultiCommand(multi.toList(), state.currentPage), _layers);
    state = state.copyWith(multiIds: const {}, clearSelection: true);
    _syncHistory();
  }

  /// Move the selected annotation. Call [beginMove] on drag start,
  /// update position during drag, then [commitMove] on drag end.
  MoveAnnotationCommand? _pendingMove;

  void beginMove(EditorAnnotation annotation) {
    if (annotation.locked) return;
    _pendingMove = MoveAnnotationCommand(annotation, annotation.pageIndex);
  }

  /// Move without committing to history (called during drag).
  SelectionSnapGuides? updateMove(EditorAnnotation annotation, Offset deltaNorm) {
    _selection.moveAnnotation(annotation, deltaNorm);
    _markDirty();
    return _selection.snapSelected(annotation, _bounds);
  }

  /// Finalise move and push to undo stack.
  void commitMove(EditorAnnotation annotation) {
    final cmd = _pendingMove;
    if (cmd == null) return;
    cmd.captureAfter(annotation);
    _pendingMove = null;
    // Don't push via _history.push here — annotation already in final position;
    // just record the command so undo can reverse it.
    _history._undoStack.add(cmd);
    _history._redoStack.clear();
    _history._dirty = true;
    _syncHistory();
  }

  void editText(TextAnnotation before, TextAnnotation after) {
    _history.push(EditTextCommand(before: before, after: after, pageIndex: state.currentPage), _layers);
    _syncHistory();
  }

  void bringToFront() {
    final sel = selected;
    if (sel == null || sel.locked) return;
    _history.push(BringToFrontCommand(sel, state.currentPage), _layers);
    _syncHistory();
  }

  void sendToBack() {
    final sel = selected;
    if (sel == null || sel.locked) return;
    // Simple: bring-to-back = remove + re-insert at index 0 via undo pattern
    final layer = layerFor(state.currentPage);
    layer.sendToBack(sel);
    _markDirty();
    _syncHistory();
  }

  // =========================================================================
  // Undo / Redo
  // =========================================================================

  bool undo() {
    final did = _history.undo(_layers);
    if (did) _syncHistory();
    return did;
  }

  bool redo() {
    final did = _history.redo(_layers);
    if (did) _syncHistory();
    return did;
  }

  // =========================================================================
  // Batch operations (multi-select)
  // =========================================================================

  void alignMulti(String how) {
    final multi = multiSelected;
    if (multi.length < 2) return;
    _selection.alignAnnotations(multi, how, _bounds);
    _markDirty();
    _syncHistory();
  }

  void distributeMulti(Axis axis) {
    final multi = multiSelected.toList();
    if (multi.length < 3) return;
    _selection.distributeAnnotations(multi, axis, _bounds);
    _markDirty();
    _syncHistory();
  }

  void duplicateSelected() {
    final sel = selected;
    if (sel == null) return;
    final copy = sel.clone(offsetNorm: 0.03);
    addAnnotation(copy);
    select(copy);
  }

  void duplicateMulti() {
    final multi = multiSelected;
    if (multi.isEmpty) return;
    final copies = <EditorAnnotation>[];
    for (final a in multi) {
      copies.add(a.clone(offsetNorm: 0.03));
    }
    for (final c in copies) {
      addAnnotation(c);
    }
    setMultiSelection(copies.toSet());
  }

  // =========================================================================
  // Clipboard
  // =========================================================================
  EditorAnnotation? _clipboard;

  void copySelected() {
    _clipboard = selected?.clone(offsetNorm: 0.0);
  }

  void paste() {
    if (_clipboard == null) return;
    final copy = _clipboard!.clone(offsetNorm: 0.03, newPageIndex: state.currentPage);
    addAnnotation(copy);
    select(copy);
  }

  // =========================================================================
  // UI overlay flags
  // =========================================================================

  void setShowFieldOverlay(bool v) => state = state.copyWith(showFieldOverlay: v);
  void setShowEditLineOverlay(bool v) => state = state.copyWith(showEditLineOverlay: v);
  void setDetecting(bool v, {String? label}) =>
      state = state.copyWith(detectingFields: v, detectingLabel: label);

  // =========================================================================
  // Helpers
  // =========================================================================

  void _markDirty() {
    state = state.copyWith(hasUnsavedChanges: true);
  }

  void _syncHistory() {
    state = state.copyWith(
      canUndo: _history.canUndo,
      canRedo: _history.canRedo,
      undoDescription: _history.nextUndoDescription,
      redoDescription: _history.nextRedoDescription,
      hasUnsavedChanges: _history.isDirty,
    );
  }

  Rect boundsOf(EditorAnnotation a) => _bounds.boundsOf(a);
}
