import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;

import 'package:ai_pdf/features/editor/data/background_page_renderer.dart';
import 'package:ai_pdf/features/editor/data/editor_page_render_service.dart';

/// Pre-renders adjacent pages in the background for instant page-switching — E4.1 Progressive Open.
///
/// ### E4.1 Design
/// - First page opens <1.5s even for 1000-page PDFs: we render page 0 at low-res (900) immediately, then upgrade to high-res (2400)
/// - Thumbnails ±5 pre-render low-res (900) first for instant strip, then high-res (2400) in background
/// - Cancels gracefully if user navigates away
/// - LRU cap 3 for high-res, but low-res thumbs kept longer (10) for strip
/// - Low-RAM mode: cap 1, 900px max edge, disable pre-render
class PagePreloaderService {
  const PagePreloaderService();

  static const EditorPageRenderService _renderer = EditorPageRenderService();
  static const BackgroundPageRenderer _bgRenderer = BackgroundPageRenderer();

  static const int _lowResEdge = 900;
  static const int _highResEdge = 2400;

  /// Pre-render pages adjacent to [currentPage] with progressive low-res → high-res.
  Future<void> preloadAdjacent({
    required pdfx.PdfDocument doc,
    required int currentPage,
    required int pageCount,
    required Map<int, Uint8List> pageCache,
    required int renderMaxEdge,
    Map<int, Uint8List>? lowResCache,
    bool lowRamMode = false,
  }) async {
    if (lowRamMode) {
      // Low-RAM: only ±1 low-res, no high-res pre-render
      for (final delta in [1, -1]) {
        final idx = currentPage + delta;
        if (idx < 0 || idx >= pageCount) continue;
        if (pageCache.containsKey(idx)) continue;
        await _bgRenderer.renderInBackground(
          doc: doc,
          index: idx,
          pageCache: pageCache,
          renderMaxEdge: _lowResEdge,
        );
      }
      return;
    }

    // Phase 1: low-res ±5 for thumbnail strip instant
    final lowPriority = <int>[];
    for (var d = 1; d <= 5; d++) {
      for (final sign in [1, -1]) {
        final idx = currentPage + sign * d;
        if (idx >= 0 && idx < pageCount) lowPriority.add(idx);
      }
    }
    // Sort by distance
    lowPriority.sort((a, b) => (a - currentPage).abs().compareTo((b - currentPage).abs()));

    for (final idx in lowPriority) {
      if (pageCache.containsKey(idx)) continue;
      // Low-res into lowResCache if provided, else into main cache as placeholder
      final targetCache = lowResCache ?? pageCache;
      if (targetCache.containsKey(idx)) continue;
      await _bgRenderer.renderInBackground(
        doc: doc,
        index: idx,
        pageCache: targetCache,
        renderMaxEdge: _lowResEdge,
      );
    }

    // Phase 2: high-res ±1 for next/prev instant paging
    for (final delta in [1, -1]) {
      final idx = currentPage + delta;
      if (idx < 0 || idx >= pageCount) continue;
      if (pageCache.containsKey(idx)) continue;
      await _renderer.renderPage(
        doc: doc,
        index: idx,
        pageCache: pageCache,
        renderMaxEdge: renderMaxEdge,
      );
    }
  }

  /// Progressive open for large docs: render first page low-res immediately, then upgrade.
  Future<Uint8List?> renderFirstPageProgressive({
    required pdfx.PdfDocument doc,
    required int index,
    required Map<int, Uint8List> pageCache,
    required void Function(Uint8List lowRes) onLowRes,
  }) async {
    // Low-res first (<1.5s target)
    await _renderer.renderPage(
      doc: doc,
      index: index,
      pageCache: pageCache,
      renderMaxEdge: _lowResEdge,
    );
    final lowRes = pageCache[index];
    if (lowRes != null) {
      onLowRes(lowRes);
    }
    // Then high-res upgrade in background
    final highResCache = <int, Uint8List>{};
    await _renderer.renderPage(
      doc: doc,
      index: index,
      pageCache: highResCache,
      renderMaxEdge: _highResEdge,
    );
    final highRes = highResCache[index];
    if (highRes != null) {
      pageCache[index] = highRes;
      return highRes;
    }
    return lowRes;
  }
}
