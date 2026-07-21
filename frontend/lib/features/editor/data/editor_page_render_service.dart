import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;

/// Stateless PDF page renderer + cache eviction policy used by the editor.
///
/// Uses the EXACT same render call as [OfflinePdfService._renderPageCapped]
/// (compress, OCR, PDF→Images, AI chat) — which works on every device. Previous
/// attempts to switch formats (PNG) or add decode-validation introduced
/// regressions on specific Android PDFium builds. This version is deliberately
/// minimal and identical to the proven path.
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
      final renderW = (page.width * scale).clamp(1, renderMaxEdge.toDouble());
      final renderH = (page.height * scale).clamp(1, renderMaxEdge.toDouble());

      // Render as JPEG — identical to OfflinePdfService._renderPageCapped which
      // works on every device (compress, OCR, PDF→Images, AI, tools). No
      // format-switching, no decode-validation, no codec wrapping. Just the
      // proven render call with the proven format.
      final rendered = await page.render(
        width: renderW.toDouble(),
        height: renderH.toDouble(),
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      if (rendered != null && rendered.bytes.isNotEmpty) {
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
