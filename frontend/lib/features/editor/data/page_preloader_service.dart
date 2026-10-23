import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;

import 'package:ai_pdf/features/editor/data/editor_page_render_service.dart';

/// Opens a page fast: a quick low-resolution frame first, then a sharp one.
///
/// The first page is drawn at 900 px at once and then replaced by a
/// 2400 px render, unless the user has moved to another page by then.
class PagePreloaderService {
  const PagePreloaderService();

  static const EditorPageRenderService _renderer = EditorPageRenderService();

  static const int _lowResEdge = 900;
  static const int _highResEdge = 2400;

  /// Progressive open for large docs: render first page low-res immediately, then upgrade.
  Future<Uint8List?> renderFirstPageProgressive({
    required pdfx.PdfDocument doc,
    required int index,
    required Map<int, Uint8List> pageCache,
    required void Function(Uint8List lowRes) onLowRes,
    Map<int, int>? resolution,
    Map<int, double>? aspects,
    Map<int, double>? pageHeights,
    bool Function()? stillCurrent,
  }) async {
    // Low-res first (<1.5s target)
    await _renderer.renderPage(
      doc: doc,
      index: index,
      pageCache: pageCache,
      renderMaxEdge: _lowResEdge,
      resolution: resolution,
      aspects: aspects,
      pageHeights: pageHeights,
      stillCurrent: stillCurrent,
    );
    final lowRes = pageCache[index];
    if (lowRes != null && (stillCurrent == null || stillCurrent())) {
      onLowRes(lowRes);
    }
    if (stillCurrent != null && !stillCurrent()) return lowRes;
    if (resolution == null) {
      // Without an edge map, any cached bytes look "done". Render the sharp
      // frame into a side buffer so it can replace the placeholder.
      final highResCache = <int, Uint8List>{};
      await _renderer.renderPage(
        doc: doc,
        index: index,
        pageCache: highResCache,
        renderMaxEdge: _highResEdge,
        aspects: aspects,
      pageHeights: pageHeights,
        stillCurrent: stillCurrent,
      );
      final highRes = highResCache[index];
      if (highRes != null && (stillCurrent == null || stillCurrent())) {
        pageCache[index] = highRes;
        return highRes;
      }
      return lowRes;
    }
    await _renderer.renderPage(
      doc: doc,
      index: index,
      pageCache: pageCache,
      renderMaxEdge: _highResEdge,
      resolution: resolution,
      aspects: aspects,
      pageHeights: pageHeights,
      stillCurrent: stillCurrent,
    );
    return pageCache[index] ?? lowRes;
  }
}
