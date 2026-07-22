import 'dart:ui' show Offset, Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_pdf/features/editor/data/redaction_service.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// A pending redaction region the user is building (before burn).
class PendingRedaction {
  final int pageIndex;
  final Rect rect;
  final String? label;

  const PendingRedaction({
    required this.pageIndex,
    required this.rect,
    this.label,
  });
}

/// UI state for the redaction tool (Phase 28).
class EditorRedactionState {
  final bool active;

  /// User has started dragging a new region.
  final Offset? dragStart;
  final Offset? dragCurrent;

  /// Regions the user has drawn but not yet burned.
  final List<PendingRedaction> pending;

  /// Number of text elements that will be erased by [pending] regions on the
  /// current page (live preview).
  final int coveredCount;

  const EditorRedactionState({
    this.active = false,
    this.dragStart,
    this.dragCurrent,
    this.pending = const [],
    this.coveredCount = 0,
  });

  bool get hasPending => pending.isNotEmpty;
  bool get isDragging => dragStart != null && dragCurrent != null;

  /// The rect being dragged (normalised 0..1).
  Rect? get liveRect {
    if (dragStart == null || dragCurrent == null) return null;
    return Rect.fromPoints(dragStart!, dragCurrent!);
  }

  EditorRedactionState copyWith({
    bool? active,
    Offset? dragStart,
    Offset? dragCurrent,
    List<PendingRedaction>? pending,
    int? coveredCount,
    bool clearDrag = false,
  }) {
    return EditorRedactionState(
      active: active ?? this.active,
      dragStart: clearDrag ? null : (dragStart ?? this.dragStart),
      dragCurrent: clearDrag ? null : (dragCurrent ?? this.dragCurrent),
      pending: pending ?? this.pending,
      coveredCount: coveredCount ?? this.coveredCount,
    );
  }
}

/// Controller for the redaction tool (Phase 28).
///
/// Manages the drag → region → preview → burn lifecycle. Delegates the actual
/// text-layer removal to [RedactionService] (Phase 17). The screen wires this
/// into a gesture detector that only fires in redaction mode.
final editorRedactionProvider =
    StateNotifierProvider<EditorRedactionController, EditorRedactionState>(
        (ref) => EditorRedactionController());

class EditorRedactionController extends StateNotifier<EditorRedactionState> {
  EditorRedactionController() : super(const EditorRedactionState());

  static const _svc = RedactionService();

  Map<int, List<PdfTextElement>> _pages = const {};
  int _currentPage = 0;

  void setPages(Map<int, List<PdfTextElement>> pages) {
    _pages = pages;
    _refreshCoveredCount();
  }

  void setCurrentPage(int page) {
    _currentPage = page;
    _refreshCoveredCount();
  }

  void activate() => state = state.copyWith(active: true);
  void deactivate() => state = const EditorRedactionState();

  /// Called on drag start (normalised 0..1 point).
  void onDragStart(Offset point) {
    state = state.copyWith(dragStart: point, dragCurrent: point);
  }

  /// Called on drag update.
  void onDragUpdate(Offset point) {
    state = state.copyWith(dragCurrent: point);
  }

  /// Called on drag end — commit the region to pending.
  void onDragEnd() {
    final rect = state.liveRect;
    if (rect == null || rect.width < 0.005 || rect.height < 0.005) {
      // Too small (accidental tap) — discard.
      state = state.copyWith(clearDrag: true);
      return;
    }
    final pending = [
      ...state.pending,
      PendingRedaction(pageIndex: _currentPage, rect: rect),
    ];
    state = state.copyWith(pending: pending, clearDrag: true);
    _refreshCoveredCount();
  }

  /// Remove the last pending region (undo one region).
  void undoLastRegion() {
    if (state.pending.isEmpty) return;
    final pending = [...state.pending]..removeLast();
    state = state.copyWith(pending: pending);
    _refreshCoveredCount();
  }

  /// Clear all pending regions without burning.
  void clearAll() {
    state = state.copyWith(pending: const [], coveredCount: 0);
  }

  /// Burn redactions into the text layer and return the result.
  ///
  /// After this call, the screen should replace the page's text-layer data
  /// with [RedactionResult.remainingText] and paint [RedactionResult.coverRects]
  /// as permanent black rectangles on the page raster.
  RedactionResult? burn() {
    final elements = _pages[_currentPage] ?? const [];
    final regions = [
      for (final p in state.pending)
        if (p.pageIndex == _currentPage) RedactionRegion(p.rect, label: p.label),
    ];
    if (regions.isEmpty) return null;
    final result = _svc.apply(elements, regions);
    // Clear pending for this page (keep other pages' pending intact).
    final remainingPending = [
      for (final p in state.pending)
        if (p.pageIndex != _currentPage) p,
    ];
    state = state.copyWith(pending: remainingPending, coveredCount: 0);
    return result;
  }

  void _refreshCoveredCount() {
    final elements = _pages[_currentPage] ?? const [];
    final regions = [
      for (final p in state.pending)
        if (p.pageIndex == _currentPage) RedactionRegion(p.rect),
    ];
    final count = _svc.coveredElements(elements, regions).length;
    state = state.copyWith(coveredCount: count);
  }
}
