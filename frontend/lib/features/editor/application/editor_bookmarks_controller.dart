import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A user-created bookmark to a specific page + annotation (Phase 44).
class EditorBookmark {
  final String id;
  final String label;
  final int pageIndex;
  final String? annotationId;
  final String? color;
  final DateTime createdAt;

  const EditorBookmark({
    required this.id,
    required this.label,
    required this.pageIndex,
    this.annotationId,
    this.color,
    required this.createdAt,
  });

  EditorBookmark copyWith({String? label, String? color}) => EditorBookmark(
        id: id,
        label: label ?? this.label,
        pageIndex: pageIndex,
        annotationId: annotationId,
        color: color ?? this.color,
        createdAt: createdAt,
      );
}

/// UI state for the bookmarks/favorites panel (Phase 44).
class EditorBookmarksState {
  final bool visible;
  final List<EditorBookmark> bookmarks;

  const EditorBookmarksState({
    this.visible = false,
    this.bookmarks = const [],
  });

  bool get hasBookmarks => bookmarks.isNotEmpty;
  int get count => bookmarks.length;

  /// Bookmarks sorted by page then creation date.
  List<EditorBookmark> get sorted => [...bookmarks]
    ..sort((a, b) {
      final p = a.pageIndex.compareTo(b.pageIndex);
      return p != 0 ? p : a.createdAt.compareTo(b.createdAt);
    });

  /// Check if a page is bookmarked.
  bool isPageBookmarked(int pageIndex) =>
      bookmarks.any((b) => b.pageIndex == pageIndex);

  EditorBookmarksState copyWith({
    bool? visible,
    List<EditorBookmark>? bookmarks,
  }) =>
      EditorBookmarksState(
        visible: visible ?? this.visible,
        bookmarks: bookmarks ?? this.bookmarks,
      );
}

/// Controller for the bookmarks/favorites system (Phase 44).
///
/// Users can bookmark pages or specific annotations for quick access.
/// Bookmarks persist across sessions (via SharedPreferences, keyed by file).
/// The panel shows a list that jumps to the bookmarked location on tap.
final editorBookmarksProvider =
    StateNotifierProvider<EditorBookmarksController, EditorBookmarksState>(
        (ref) => EditorBookmarksController());

class EditorBookmarksController extends StateNotifier<EditorBookmarksState> {
  EditorBookmarksController() : super(const EditorBookmarksState());

  int _nextId = 1;

  void show() => state = state.copyWith(visible: true);
  void hide() => state = state.copyWith(visible: false);
  void toggle() => state = state.copyWith(visible: !state.visible);

  /// Add a bookmark for the current page.
  EditorBookmark add({
    required String label,
    required int pageIndex,
    String? annotationId,
    String? color,
  }) {
    final bookmark = EditorBookmark(
      id: 'bm_${_nextId++}',
      label: label,
      pageIndex: pageIndex,
      annotationId: annotationId,
      color: color,
      createdAt: DateTime.now(),
    );
    state = state.copyWith(bookmarks: [...state.bookmarks, bookmark]);
    return bookmark;
  }

  /// Quick-toggle: add bookmark if not bookmarked, remove if already is.
  void togglePage(int pageIndex, {String? defaultLabel}) {
    final existing = state.bookmarks
        .cast<EditorBookmark?>()
        .firstWhere((b) => b?.pageIndex == pageIndex && b?.annotationId == null,
            orElse: () => null);
    if (existing != null) {
      delete(existing.id);
    } else {
      add(
        label: defaultLabel ?? 'Page ${pageIndex + 1}',
        pageIndex: pageIndex,
      );
    }
  }

  /// Rename a bookmark.
  void rename(String id, String newLabel) {
    state = state.copyWith(
      bookmarks: [
        for (final b in state.bookmarks)
          if (b.id == id) b.copyWith(label: newLabel) else b,
      ],
    );
  }

  /// Set a color for a bookmark.
  void setColor(String id, String color) {
    state = state.copyWith(
      bookmarks: [
        for (final b in state.bookmarks)
          if (b.id == id) b.copyWith(color: color) else b,
      ],
    );
  }

  /// Delete a bookmark.
  void delete(String id) {
    state = state.copyWith(
      bookmarks: [for (final b in state.bookmarks) if (b.id != id) b],
    );
  }

  /// Delete all bookmarks for a specific page.
  void deleteForPage(int pageIndex) {
    state = state.copyWith(
      bookmarks: [
        for (final b in state.bookmarks) if (b.pageIndex != pageIndex) b,
      ],
    );
  }

  /// Load bookmarks from persistence.
  void loadAll(List<EditorBookmark> bookmarks) {
    state = state.copyWith(bookmarks: bookmarks);
  }

  void clear() {
    state = const EditorBookmarksState();
    _nextId = 1;
  }
}
