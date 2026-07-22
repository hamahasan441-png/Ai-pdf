import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;

import 'package:ai_pdf/features/editor/data/editor_page_render_service.dart';

/// Pre-renders adjacent pages in the background for instant page-switching.
///
/// When the user is on page N, this service ensures pages N-1 and N+1 are
/// already rendered in the cache. This makes paging feel instant rather than
/// showing a loading indicator for every page turn.
///
/// ### Memory safety
/// Only 3 pages are cached at any time (the eviction policy in
/// [EditorPageRenderService.evictFarPages] handles cleanup). This service only
/// TRIGGERS rendering — it doesn't bypass the cap.
class PagePreloaderService {
  const PagePreloaderService();

  static const EditorPageRenderService _renderer = EditorPageRenderService();

  /// Pre-render pages adjacent to [currentPage].
  /// Call this after each page navigation completes.
  Future<void> preloadAdjacent({
    required pdfx.PdfDocument doc,
    required int currentPage,
    required int pageCount,
    required Map<int, Uint8List> pageCache,
    required int renderMaxEdge,
  }) async {
    // Pre-render next page (most likely to be navigated to).
    if (currentPage + 1 < pageCount) {
      await _renderer.renderPage(
        doc: doc,
        index: currentPage + 1,
        pageCache: pageCache,
        renderMaxEdge: renderMaxEdge,
      );
    }
    // Then previous page.
    if (currentPage - 1 >= 0) {
      await _renderer.renderPage(
        doc: doc,
        index: currentPage - 1,
        pageCache: pageCache,
        renderMaxEdge: renderMaxEdge,
      );
    }
  }
}
