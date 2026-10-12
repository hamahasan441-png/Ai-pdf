import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;

import 'package:ai_pdf/features/editor/data/page_cache_policy.dart';

/// Stateless PDF page renderer + cache eviction policy used by the editor.
///
/// Uses the EXACT same render call as [OfflinePdfService._renderPageCapped]
/// (compress, OCR, PDF→Images, AI chat) — which works on every device.
///
/// PDFium (via pdfx) is not safe to render the same document on overlapping
/// calls, and doing so is slower, not faster. Renders for one document are
/// therefore queued, and two callers asking for the same page size share one
/// in-flight future.
class EditorPageRenderService {
  const EditorPageRenderService();

  static final Map<String, Future<void>> _inflight = {};
  static final Map<int, Future<void>> _docChain = {};

  Future<void> renderPage({
    required pdfx.PdfDocument doc,
    required int index,
    required Map<int, Uint8List> pageCache,
    required int renderMaxEdge,
    Map<int, int>? resolution,
    bool Function()? stillCurrent,
  }) {
    if (_freshEnough(pageCache, resolution, index, renderMaxEdge)) {
      return Future<void>.value();
    }

    final docId = identityHashCode(doc);
    final key = '$docId:$index:$renderMaxEdge';
    final existing = _inflight[key];
    if (existing != null) return existing;

    final previous = _docChain[docId] ?? Future<void>.value();
    final flight = previous.catchError((Object _) {}).then((_) async {
      if (_freshEnough(pageCache, resolution, index, renderMaxEdge)) return;
      if (stillCurrent != null && !stillCurrent()) return;
      await _render(
        doc: doc,
        index: index,
        pageCache: pageCache,
        renderMaxEdge: renderMaxEdge,
        resolution: resolution,
        stillCurrent: stillCurrent,
      );
    });
    _inflight[key] = flight;
    _docChain[docId] = flight;
    return flight.whenComplete(() {
      if (identical(_inflight[key], flight)) _inflight.remove(key);
      if (identical(_docChain[docId], flight)) _docChain.remove(docId);
    });
  }

  bool _freshEnough(
    Map<int, Uint8List> pageCache,
    Map<int, int>? resolution,
    int index,
    int renderMaxEdge,
  ) {
    return PageCachePolicy.shouldSkip(
      hasBytes: pageCache.containsKey(index),
      cachedEdge: resolution?[index],
      requestedEdge: renderMaxEdge,
      tracksResolution: resolution != null,
    );
  }

  Future<void> _render({
    required pdfx.PdfDocument doc,
    required int index,
    required Map<int, Uint8List> pageCache,
    required int renderMaxEdge,
    Map<int, int>? resolution,
    bool Function()? stillCurrent,
  }) async {
    final page = await doc.getPage(index + 1);
    try {
      if (stillCurrent != null && !stillCurrent()) return;
      final longEdge = page.width > page.height ? page.width : page.height;
      final scale = longEdge > renderMaxEdge ? renderMaxEdge / longEdge : 1.0;
      final renderW = (page.width * scale).clamp(1, renderMaxEdge.toDouble());
      final renderH = (page.height * scale).clamp(1, renderMaxEdge.toDouble());

      final rendered = await page.render(
        width: renderW.toDouble(),
        height: renderH.toDouble(),
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      if (stillCurrent != null && !stillCurrent()) return;
      if (rendered == null || rendered.bytes.isEmpty) return;
      if (!PageCachePolicy.shouldStore(
        cachedEdge: resolution?[index],
        renderedEdge: renderMaxEdge,
      )) {
        return;
      }
      pageCache[index] = rendered.bytes;
      if (resolution != null) resolution[index] = renderMaxEdge;
    } finally {
      await page.close();
    }
  }

  /// Bound memory: drop rendered bytes for pages far from [keepIndex].
  void evictFarPages({
    required Map<int, Uint8List> pageCache,
    required int keepIndex,
    required int maxCachedPages,
    Map<int, int>? resolution,
  }) {
    if (pageCache.length <= maxCachedPages) return;
    final toRemove = pageCache.keys
        .where((k) => (k - keepIndex).abs() > 1)
        .toList()
      ..sort((a, b) => (b - keepIndex).abs().compareTo((a - keepIndex).abs()));
    for (final k in toRemove) {
      if (pageCache.length <= maxCachedPages) break;
      pageCache.remove(k);
      resolution?.remove(k);
    }
  }
}
