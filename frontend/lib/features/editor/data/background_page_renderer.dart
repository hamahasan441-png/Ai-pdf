import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:pdfx/pdfx.dart' as pdfx;

import 'package:ai_pdf/features/editor/data/editor_page_render_service.dart';

/// Background page renderer that schedules heavy JPEG-decode work on an
/// isolate via [compute], keeping the UI thread smooth during page transitions
/// and multi-page preloading.
///
/// ### Architecture
/// The pdfx render call is already async/native-threaded. The bottleneck on
/// low-end devices is actually the Dart-side JPEG reencode / decode step that
/// happens when the bytes arrive back on the main isolate (triggering image
/// codec work). This service:
/// 1. Renders pages via the existing [EditorPageRenderService] (async).
/// 2. Optionally downscales large pages in a background isolate before
///    injecting them into the cache, bounding memory without blocking the UI.
///
/// ### When to use
/// Call [renderInBackground] instead of the synchronous [renderPage] when the
/// page is not immediately needed (e.g. preloading adjacent pages). The user-
/// facing current-page render still uses the direct path for lowest latency.
class BackgroundPageRenderer {
  const BackgroundPageRenderer();

  static const EditorPageRenderService _renderer = EditorPageRenderService();

  /// Render page [index] in the background. If the page is already cached,
  /// this is a no-op. The result is placed directly into [pageCache].
  Future<void> renderInBackground({
    required pdfx.PdfDocument doc,
    required int index,
    required Map<int, Uint8List> pageCache,
    required int renderMaxEdge,
    int? downscaleMaxEdge,
    Map<int, int>? resolution,
    bool Function()? stillCurrent,
  }) async {
    if (pageCache.containsKey(index) && resolution == null) return;

    // Step 1: render via pdfx (native async, serialized per document).
    await _renderer.renderPage(
      doc: doc,
      index: index,
      pageCache: pageCache,
      renderMaxEdge: renderMaxEdge,
      resolution: resolution,
      stillCurrent: stillCurrent,
    );

    // The renderer already capped the long edge. Decoding that JPEG just to
    // discover it is small enough is pure main-isolate waste — skip it.
    if (downscaleMaxEdge == null || downscaleMaxEdge >= renderMaxEdge) return;
    if (stillCurrent != null && !stillCurrent()) return;

    // Step 2: optionally downscale on a background isolate to save memory.
    if (pageCache.containsKey(index)) {
      final bytes = pageCache[index]!;
      final scaled = await compute(
        _downscaleJpeg,
        _DownscaleParams(bytes: bytes, maxEdge: downscaleMaxEdge),
      );
      if (stillCurrent != null && !stillCurrent()) return;
      // Don't clobber a sharper bitmap that landed while we were decoding.
      if (scaled != null && identical(pageCache[index], bytes)) {
        pageCache[index] = scaled;
        if (resolution != null) resolution[index] = downscaleMaxEdge;
      }
    }
  }

  /// Evict pages far from [keepIndex] (delegates to the base service).
  void evictFarPages({
    required Map<int, Uint8List> pageCache,
    required int keepIndex,
    required int maxCachedPages,
    Map<int, int>? resolution,
  }) {
    _renderer.evictFarPages(
      pageCache: pageCache,
      keepIndex: keepIndex,
      maxCachedPages: maxCachedPages,
      resolution: resolution,
    );
  }
}

/// Parameters for the isolate downscale function.
class _DownscaleParams {
  final Uint8List bytes;
  final int maxEdge;
  const _DownscaleParams({required this.bytes, required this.maxEdge});
}

/// Pure function run on a background isolate via [compute].
/// Decodes a JPEG, downscales if larger than [params.maxEdge], and re-encodes.
/// Returns null if decoding fails (caller keeps the original bytes).
Uint8List? _downscaleJpeg(_DownscaleParams params) {
  try {
    final decoded = img.decodeJpg(params.bytes);
    if (decoded == null) return null;
    final longEdge = decoded.width > decoded.height ? decoded.width : decoded.height;
    if (longEdge <= params.maxEdge) return null; // already small enough
    final scaled = img.copyResize(
      decoded,
      width: decoded.width > decoded.height ? params.maxEdge : null,
      height: decoded.height >= decoded.width ? params.maxEdge : null,
      interpolation: img.Interpolation.linear,
    );
    return Uint8List.fromList(img.encodeJpg(scaled, quality: 82));
  } catch (_) {
    return null;
  }
}
