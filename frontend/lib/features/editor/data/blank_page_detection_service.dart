import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// Thresholds for deciding a page is blank (Phase 26).
class BlankPageConfig {
  /// A page with fewer than this many non‑whitespace characters is a text
  /// candidate for "blank".
  final int minChars;

  /// When per‑page ink coverage is available, a page with at least this
  /// fraction of non‑white pixels is treated as non‑blank (catches scanned /
  /// image‑only pages that have no text layer).
  final double minInkCoverage;

  const BlankPageConfig({this.minChars = 2, this.minInkCoverage = 0.005});
}

/// Per‑page blank analysis result.
class PageBlankResult {
  final int pageIndex;

  /// Count of non‑whitespace characters found in the text layer.
  final int visibleChars;

  /// Fraction of non‑white pixels (0..1), if it was supplied; else null.
  final double? inkCoverage;

  final bool isBlank;

  const PageBlankResult({
    required this.pageIndex,
    required this.visibleChars,
    required this.inkCoverage,
    required this.isBlank,
  });
}

/// Detects blank / near‑blank pages so the editor can offer "remove blank
/// pages" and warn before export (Phase 26).
///
/// Works primarily off the native text layer (non‑whitespace character count).
/// Because a scanned, image‑only page has no text layer yet clearly isn't
/// blank, an optional per‑page ink‑coverage map (fraction of non‑white pixels)
/// can be supplied to avoid false positives.
///
/// Pure Dart, no Flutter dependency → fully unit‑testable.
class BlankPageDetectionService {
  const BlankPageDetectionService();

  /// Analyse every page. [inkCoverage] (optional) maps a page index to its
  /// fraction of non‑white pixels.
  List<PageBlankResult> analyze(
    Map<int, List<PdfTextElement>> pages, {
    Map<int, double>? inkCoverage,
    BlankPageConfig config = const BlankPageConfig(),
  }) {
    final pageSet = <int>{...pages.keys, ...?inkCoverage?.keys};
    final ordered = pageSet.toList()..sort();

    final results = <PageBlankResult>[];
    for (final pageIndex in ordered) {
      final elements = pages[pageIndex] ?? const [];
      final chars = _visibleChars(elements);
      final ink = inkCoverage?[pageIndex];

      final textBlank = chars < config.minChars;
      final inkBlank = ink == null ? true : ink < config.minInkCoverage;
      final isBlank = textBlank && inkBlank;

      results.add(PageBlankResult(
        pageIndex: pageIndex,
        visibleChars: chars,
        inkCoverage: ink,
        isBlank: isBlank,
      ));
    }
    return results;
  }

  /// Indices of pages judged blank.
  List<int> blankPages(
    Map<int, List<PdfTextElement>> pages, {
    Map<int, double>? inkCoverage,
    BlankPageConfig config = const BlankPageConfig(),
  }) {
    return [
      for (final r in analyze(pages, inkCoverage: inkCoverage, config: config))
        if (r.isBlank) r.pageIndex,
    ];
  }

  int _visibleChars(List<PdfTextElement> elements) {
    var count = 0;
    for (final e in elements) {
      count += e.text.replaceAll(RegExp(r'\s+'), '').length;
    }
    return count;
  }
}
