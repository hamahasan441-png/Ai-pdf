import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A review comment attached to an annotation (Phase 40).
class AnnotationComment {
  final String id;
  final String annotationId;
  final int pageIndex;
  final String author;
  final String text;
  final DateTime createdAt;
  final bool resolved;

  const AnnotationComment({
    required this.id,
    required this.annotationId,
    required this.pageIndex,
    required this.author,
    required this.text,
    required this.createdAt,
    this.resolved = false,
  });

  AnnotationComment copyWith({String? text, bool? resolved}) =>
      AnnotationComment(
        id: id,
        annotationId: annotationId,
        pageIndex: pageIndex,
        author: author,
        text: text ?? this.text,
        createdAt: createdAt,
        resolved: resolved ?? this.resolved,
      );
}

/// UI state for the annotation comments/review panel (Phase 40).
class EditorCommentsState {
  final bool visible;
  final List<AnnotationComment> comments;
  final bool showResolved;
  final String? selectedAnnotationId;

  const EditorCommentsState({
    this.visible = false,
    this.comments = const [],
    this.showResolved = false,
    this.selectedAnnotationId,
  });

  int get totalCount => comments.length;
  int get unresolvedCount => comments.where((c) => !c.resolved).length;
  int get resolvedCount => comments.where((c) => c.resolved).length;

  List<AnnotationComment> get visibleComments => showResolved
      ? comments
      : comments.where((c) => !c.resolved).toList();

  /// Comments for a specific annotation.
  List<AnnotationComment> forAnnotation(String annotationId) =>
      comments.where((c) => c.annotationId == annotationId).toList();

  EditorCommentsState copyWith({
    bool? visible,
    List<AnnotationComment>? comments,
    bool? showResolved,
    String? selectedAnnotationId,
    bool clearSelection = false,
  }) =>
      EditorCommentsState(
        visible: visible ?? this.visible,
        comments: comments ?? this.comments,
        showResolved: showResolved ?? this.showResolved,
        selectedAnnotationId: clearSelection
            ? null
            : (selectedAnnotationId ?? this.selectedAnnotationId),
      );
}

/// Controller for the annotation comments/review system (Phase 40).
///
/// Enables collaborative review: add comments to any annotation, resolve them,
/// filter by resolved/unresolved. Comments are stored per-document and can be
/// exported as a review summary. The "select annotation" action highlights it
/// and scrolls the page.
final editorCommentsProvider =
    StateNotifierProvider<EditorCommentsController, EditorCommentsState>(
        (ref) => EditorCommentsController());

class EditorCommentsController extends StateNotifier<EditorCommentsState> {
  EditorCommentsController() : super(const EditorCommentsState());

  int _nextId = 1;

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  void toggleShowResolved() =>
      state = state.copyWith(showResolved: !state.showResolved);

  /// Add a comment to an annotation.
  AnnotationComment add({
    required String annotationId,
    required int pageIndex,
    required String author,
    required String text,
  }) {
    final comment = AnnotationComment(
      id: 'comment_${_nextId++}',
      annotationId: annotationId,
      pageIndex: pageIndex,
      author: author,
      text: text,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(comments: [...state.comments, comment]);
    return comment;
  }

  /// Edit a comment's text.
  void edit(String commentId, String newText) {
    state = state.copyWith(
      comments: [
        for (final c in state.comments)
          if (c.id == commentId) c.copyWith(text: newText) else c,
      ],
    );
  }

  /// Resolve a comment (mark as addressed).
  void resolve(String commentId) {
    state = state.copyWith(
      comments: [
        for (final c in state.comments)
          if (c.id == commentId) c.copyWith(resolved: true) else c,
      ],
    );
  }

  /// Unresolve a comment.
  void unresolve(String commentId) {
    state = state.copyWith(
      comments: [
        for (final c in state.comments)
          if (c.id == commentId) c.copyWith(resolved: false) else c,
      ],
    );
  }

  /// Delete a comment.
  void delete(String commentId) {
    state = state.copyWith(
      comments: [
        for (final c in state.comments)
          if (c.id != commentId) c,
      ],
    );
  }

  /// Resolve all comments for a specific annotation.
  void resolveAllFor(String annotationId) {
    state = state.copyWith(
      comments: [
        for (final c in state.comments)
          if (c.annotationId == annotationId) c.copyWith(resolved: true) else c,
      ],
    );
  }

  /// Select an annotation to highlight + scroll to.
  void selectAnnotation(String? annotationId) {
    state = state.copyWith(
      selectedAnnotationId: annotationId,
      clearSelection: annotationId == null,
    );
  }

  /// Load comments from persistence (e.g. JSON stored alongside annotations).
  void loadAll(List<AnnotationComment> comments) {
    state = state.copyWith(comments: comments);
  }

  /// Export a plain-text review summary.
  String exportSummary() {
    final buf = StringBuffer();
    buf.writeln('=== Review Comments ===\n');
    for (final c in state.comments) {
      final status = c.resolved ? '[RESOLVED]' : '[OPEN]';
      buf.writeln('$status Page ${c.pageIndex + 1} | ${c.author} | ${_fmt(c.createdAt)}');
      buf.writeln('  ${c.text}\n');
    }
    buf.writeln('Total: ${state.totalCount} (${state.unresolvedCount} open, ${state.resolvedCount} resolved)');
    return buf.toString();
  }

  void reset() {
    state = const EditorCommentsState();
    _nextId = 1;
  }

  String _fmt(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
}
