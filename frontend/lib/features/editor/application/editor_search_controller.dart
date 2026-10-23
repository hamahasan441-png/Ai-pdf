import 'dart:ui' show Rect;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_pdf/features/editor/data/document_search_service.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// UI state for the in-document search feature (Phase 27).
class EditorSearchState {
  final bool active;
  final String query;
  final SearchOptions options;
  final List<SearchMatch> matches;
  final int currentMatchIndex;

  const EditorSearchState({
    this.active = false,
    this.query = '',
    this.options = const SearchOptions(),
    this.matches = const [],
    this.currentMatchIndex = -1,
  });

  int get matchCount => matches.length;
  bool get hasMatches => matches.isNotEmpty;

  SearchMatch? get currentMatch =>
      currentMatchIndex >= 0 && currentMatchIndex < matches.length
          ? matches[currentMatchIndex]
          : null;

  /// The page the active match lives on (or -1 if none).
  int get currentPage => currentMatch?.pageIndex ?? -1;

  /// Highlight rects for a specific page (so the painter only draws relevant
  /// matches).
  List<Rect> rectsForPage(int pageIndex) => [
        for (final m in matches)
          if (m.pageIndex == pageIndex) m.rect,
      ];

  /// Badge text like "3/14".
  String get badge => hasMatches ? '${currentMatchIndex + 1}/$matchCount' : '0/0';

  EditorSearchState copyWith({
    bool? active,
    String? query,
    SearchOptions? options,
    List<SearchMatch>? matches,
    int? currentMatchIndex,
  }) {
    return EditorSearchState(
      active: active ?? this.active,
      query: query ?? this.query,
      options: options ?? this.options,
      matches: matches ?? this.matches,
      currentMatchIndex: currentMatchIndex ?? this.currentMatchIndex,
    );
  }
}

class EditorSearchController extends StateNotifier<EditorSearchState> {
  /// The current state, for widgets that own this controller directly
  /// (StateNotifier keeps [state] protected).
  EditorSearchState get current => state;

  EditorSearchController() : super(const EditorSearchState());

  static const _svc = DocumentSearchService();

  /// Text layer of the open document, kept up to date by the screen whenever
  /// the document or page extraction changes.
  Map<int, List<PdfTextElement>> _pages = const {};

  /// The text layer the current matches index into.
  Map<int, List<PdfTextElement>> get pages => _pages;

  /// The matches a replace acts on: every match, or only the current one.
  List<SearchMatch> matchesToReplace({required bool all}) {
    final current = state.currentMatch;
    return all ? state.matches : [if (current != null) current];
  }

  void setPages(Map<int, List<PdfTextElement>> pages) {
    _pages = pages;
    // The same query on a changed layer (for example after a replace) stays
    // at the same match number, which is now the next match.
    if (state.active && state.query.isNotEmpty) _run(keepPosition: true);
  }

  void open() {
    state = state.copyWith(active: true);
  }

  void close() {
    state = const EditorSearchState();
  }

  void setQuery(String query) {
    state = state.copyWith(query: query);
    _run();
  }

  void setCaseSensitive(bool value) {
    state = state.copyWith(
      options: SearchOptions(
        caseSensitive: value,
        wholeWord: state.options.wholeWord,
      ),
    );
    _run();
  }

  void setWholeWord(bool value) {
    state = state.copyWith(
      options: SearchOptions(
        caseSensitive: state.options.caseSensitive,
        wholeWord: value,
      ),
    );
    _run();
  }

  void next() {
    state = state.copyWith(
      currentMatchIndex: _svc.nextIndex(state.currentMatchIndex, state.matchCount),
    );
  }

  void previous() {
    state = state.copyWith(
      currentMatchIndex:
          _svc.previousIndex(state.currentMatchIndex, state.matchCount),
    );
  }

  void _run({bool keepPosition = false}) {
    final matches = _svc.search(_pages, state.query, options: state.options);
    final keep = keepPosition && state.currentMatchIndex >= 0 ? state.currentMatchIndex : 0;
    final idx = matches.isEmpty ? -1 : (keep < matches.length ? keep : 0);
    state = state.copyWith(matches: matches, currentMatchIndex: idx);
  }
}
