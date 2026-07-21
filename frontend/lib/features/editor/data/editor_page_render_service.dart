import 'dart:typed_data';
import 'dart:ui' as ui;

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
      final w = (page.width * scale).clamp(1.0, renderMaxEdge.toDouble()).toDouble();
      final h = (page.height * scale).clamp(1.0, renderMaxEdge.toDouble()).toDouble();

      // Render as JPEG FIRST. This is the exact format every other PDF screen in
      // the app renders with successfully (compress, OCR, PDF->images, AI, tools
      // via OfflinePdfService._renderPageCapped). An earlier change switched the
      // editor to PNG to work around a device-specific "unusable buffer", but on
      // some Android PDFium builds PNG comes back TRANSPARENT/blank — the bytes
      // decode fine (non-zero size) yet nothing is visible, so the editor canvas
      // was completely dark even though the page count loaded. JPEG is opaque and
      // proven across the app; PNG is kept only as a fallback for the rare device
      // where JPEG cannot be decoded.
      final bytes =
          await _renderValidated(page, w, h, pdfx.PdfPageImageFormat.jpeg) ??
              await _renderValidated(page, w, h, pdfx.PdfPageImageFormat.png);
      if (bytes != null) {
        pageCache[index] = bytes;
      }
    } finally {
      await page.close();
    }
  }

  /// Render [page] at [w]x[h] in [format]. Returns the bytes ONLY if they are
  /// non-empty and decode to a valid, non-zero image; otherwise returns null so
  /// the caller can fall back to another format.
  Future<Uint8List?> _renderValidated(
    pdfx.PdfPage page,
    double w,
    double h,
    pdfx.PdfPageImageFormat format,
  ) async {
    try {
      final rendered = await page.render(
        width: w,
        height: h,
        format: format,
        backgroundColor: '#FFFFFF',
      );
      final bytes = rendered?.bytes;
      if (bytes == null || bytes.isEmpty) return null;

      // Confirm the bytes are genuinely decodable (guards against a non-empty
      // but corrupt/unusable buffer).
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final valid = image.width > 0 && image.height > 0;
        image.dispose();
        return valid ? bytes : null;
      } finally {
        codec.dispose();
      }
    } catch (_) {
      return null;
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
