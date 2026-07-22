import 'dart:ui' show Rect;

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// A single search hit inside the document's native text layer.
///
/// Coordinates are the same normalised 0..1 page space used by
/// [PdfTextElement.rect] and the rest of the editor, so a match can be
/// highlighted directly on the page without any extra transform.
class SearchMatch {
  /// Zero-based page the match lives on.
  final int pageIndex;

  /// Index of the matched element within that page's element list.
  final int elementIndex;

  /// The exact text that matched (as it appears in the source element).
  final String text;

  /// Character offset of the match start within the element's text.
  final int start;

  /// Character offset just past the match end within the element's text.
  final int end;

  /// Normalised bounding rect of the *element* that contains the match.
  final Rect rect;

  const SearchMatch({
    required this.pageIndex,
    required this.elementIndex,
    required this.text,
    required this.start,
    required this.end,
    required this.rect,
  });

  @override
  String toString() =>
      'SearchMatch(p$pageIndex, e$elementIndex, [$start,$end) "$text")';
}

/// Options controlling how [DocumentSearchService.search] matches.
class SearchOptions {
  final bool caseSensitive;
  final bool wholeWord;

  const SearchOptions({this.caseSensitive = false, this.wholeWord = false});
}

/// In-document search over the native PDF text layer (Phase 12).
///
/// Works on the positioned text produced by [TextLayerExtractionService]
/// (`Map<pageIndex, List<PdfTextElement>>`). It finds every occurrence of a
/// query — including multiple hits inside a single element — in reading order
/// (page ascending, then the element order returned by extraction), and returns
/// [SearchMatch]es that can be highlighted and stepped through with
/// next / previous navigation.
///
/// Pure Dart (no Flutter widget dependencies) so it is fully unit-testable and
/// can run in a background isolate for large documents.
class DocumentSearchService {
  const DocumentSearchService();

  /// Find every occurrence of [query] across all pages.
  ///
  /// Returns matches ordered by page, then element, then position. An empty or
  /// whitespace-only query yields no matches.
  List<SearchMatch> search(
    Map<int, List<PdfTextElement>> pages,
    String query, {
    SearchOptions options = const SearchOptions(),
  }) {
    final needle = options.caseSensitive ? query : query.toLowerCase();
    if (needle.trim().isEmpty) return const [];

    final matches = <SearchMatch>[];
    final pageIndexes = pages.keys.toList()..sort();

    for (final pageIndex in pageIndexes) {
      final elements = pages[pageIndex] ?? const [];
      for (var e = 0; e < elements.length; e++) {
        final element = elements[e];
        final haystack =
            options.caseSensitive ? element.text : element.text.toLowerCase();

        var from = 0;
        while (true) {
          final idx = haystack.indexOf(needle, from);
          if (idx < 0) break;
          final matchEnd = idx + needle.length;
          if (!options.wholeWord ||
              _isWholeWord(haystack, idx, matchEnd)) {
            matches.add(SearchMatch(
              pageIndex: pageIndex,
              elementIndex: e,
              text: element.text.substring(idx, matchEnd),
              start: idx,
              end: matchEnd,
              rect: element.rect,
            ));
          }
          // Advance by at least one char so zero-width edge cases can't loop.
          from = matchEnd > idx ? matchEnd : idx + 1;
        }
      }
    }
    return matches;
  }

  /// Convenience count without materialising navigation state.
  int count(
    Map<int, List<PdfTextElement>> pages,
    String query, {
    SearchOptions options = const SearchOptions(),
  }) =>
      search(pages, query, options: options).length;

  /// The next match index after [current], wrapping around to 0.
  ///
  /// Returns -1 when there are no matches. Passing -1 as [current] (the
  /// "nothing selected yet" state) yields the first match.
  int nextIndex(int current, int total) {
    if (total <= 0) return -1;
    if (current < 0) return 0;
    return (current + 1) % total;
  }

  /// The previous match index before [current], wrapping to the last match.
  int previousIndex(int current, int total) {
    if (total <= 0) return -1;
    if (current <= 0) return total - 1;
    return current - 1;
  }

  bool _isWholeWord(String haystack, int start, int end) {
    final before = start == 0 ? null : haystack.codeUnitAt(start - 1);
    final after = end >= haystack.length ? null : haystack.codeUnitAt(end);
    return !_isWordChar(before) && !_isWordChar(after);
  }

  bool _isWordChar(int? c) {
    if (c == null) return false;
    // ASCII letters/digits/underscore. Non-ASCII (e.g. Arabic) is treated as a
    // word char so whole-word search stays sensible for RTL scripts.
    final isDigit = c >= 0x30 && c <= 0x39;
    final isUpper = c >= 0x41 && c <= 0x5A;
    final isLower = c >= 0x61 && c <= 0x7A;
    final isUnderscore = c == 0x5F;
    final isNonAscii = c > 0x7F;
    return isDigit || isUpper || isLower || isUnderscore || isNonAscii;
  }
}
