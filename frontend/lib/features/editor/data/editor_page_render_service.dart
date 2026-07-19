import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;

/// Stateless PDF page renderer + cache eviction policy used by the editor.
///
/// The editor screen still owns UI state, current page selection, and loading
/// indicators; this service owns only the mechanical page rasterization and the
/// memory-bounding cache trimming policy.
class EditorPageRenderService {
  const EditorPageRenderService();

  Future<void> renderPage({
    required pdfx.PdfDocument doc,
    required int index,
    required Map<int, Uint8List> pageCache,
    required int renderMaxEdge,
  }) async {
    if (pageCache.containsKey(index)) return;
    final page = await doc.getPage(index + 1);
    try {
      final longEdge = page.width > page.height ? page.width : page.height;
      final scale = longEdge > renderMaxEdge ? renderMaxEdge / longEdge : 1.0;
      final rendered = await page.render(
        width: page.width * scale,
        height: page.height * scale,
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      if (rendered != null) {
        pageCache[index] = rendered.bytes;
      }
    } finally {
      await page.close();
    }
  }

  /// Bound memory: drop rendered bytes for pages far from [keepIndex].
  /// Annotation layers (tiny) are retained elsewhere so edits are never lost.
  void evictFarPages({
    required Map<int, Uint8List> pageCache,
    required int keepIndex,
    required int maxCachedPages,
  }) {
    if (pageCache.length <= maxCachedPages) return;
    final toRemove = pageCache.keys
        .where((k) => (k - keepIndex).abs() > 1)
        .toList()
      ..sort((a, b) => (b - keepIndex).abs().compareTo((a - keepIndex).abs()));
    for (final k in toRemove) {
      if (pageCache.length <= maxCachedPages) break;
      pageCache.remove(k);
    }
  }
}
