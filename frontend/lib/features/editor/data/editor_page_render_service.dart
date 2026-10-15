import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:pdfx/pdfx.dart' as pdfx;

import 'package:ai_pdf/features/editor/data/page_cache_policy.dart';

/// Identity of one in-flight render. Two callers that do not share a cache
/// must not share a future: the render writes into exactly one map.
@visibleForTesting
String renderFlightKey({
  required int docId,
  required int cacheId,
  required int pageIndex,
  required int edge,
}) =>
    '$docId:$cacheId:$pageIndex:$edge';

/// Gates for one shared render. The render proceeds while any caller still
/// wants it, so a cancelled neighbour cannot abort a live page.
class RenderRequestGates {
  final List<bool Function()> _gates = [];

  void add(bool Function() gate) => _gates.add(gate);

  void remove(bool Function() gate) => _gates.remove(gate);

  bool get isEmpty => _gates.isEmpty;

  bool get anyStillCurrent {
    for (final gate in _gates) {
      try {
        if (gate()) return true;
      } catch (_) {
        // A disposed caller must not cancel everyone else.
      }
    }
    return false;
  }
}

/// Stateless PDF page renderer + cache eviction policy used by the editor.
///
/// PDFium (via pdfx) is not safe to render the same document on overlapping
/// calls. Renders for one document are queued. Callers that ask for the same
/// document, the same cache map, the same page, and the same edge share one
/// in-flight future. A different cache gets its own future so it cannot be
/// left empty.
class EditorPageRenderService {
  const EditorPageRenderService();

  static final Map<String, _RenderSlot> _slots = {};
  static final Map<int, Future<void>> _docChain = {};

  Future<void> renderPage({
    required pdfx.PdfDocument doc,
    required int index,
    required Map<int, Uint8List> pageCache,
    required int renderMaxEdge,
    Map<int, int>? resolution,
    Map<int, double>? aspects,
    Map<int, double>? pageHeights,
    bool Function()? stillCurrent,
  }) {
    if (_freshEnough(pageCache, resolution, index, renderMaxEdge)) {
      return Future<void>.value();
    }

    final docId = identityHashCode(doc);
    final key = renderFlightKey(
      docId: docId,
      cacheId: identityHashCode(pageCache),
      pageIndex: index,
      edge: renderMaxEdge,
    );
    final slot = _slots.putIfAbsent(key, _RenderSlot.new);
    bool callerWants() => stillCurrent == null || stillCurrent();
    slot.gates.add(callerWants);

    final existing = slot.flight;
    if (existing != null) {
      return existing.whenComplete(() {
        slot.gates.remove(callerWants);
      }).then((_) async {
        if (!callerWants()) return;
        if (_freshEnough(pageCache, resolution, index, renderMaxEdge)) return;
        // The shared attempt did not fill this cache. Try once more.
        await _enqueue(
          docId: docId,
          doc: doc,
          index: index,
          pageCache: pageCache,
          renderMaxEdge: renderMaxEdge,
          resolution: resolution,
          aspects: aspects,
          pageHeights: pageHeights,
          stillCurrent: callerWants,
        );
      });
    }

    final flight = _enqueue(
      docId: docId,
      doc: doc,
      index: index,
      pageCache: pageCache,
      renderMaxEdge: renderMaxEdge,
      resolution: resolution,
      aspects: aspects,
      pageHeights: pageHeights,
      stillCurrent: () => slot.gates.anyStillCurrent,
    );
    slot.flight = flight;
    return flight.whenComplete(() {
      slot.gates.remove(callerWants);
      if (identical(slot.flight, flight)) slot.flight = null;
      if (slot.gates.isEmpty && slot.flight == null) _slots.remove(key);
    });
  }

  Future<void> _enqueue({
    required int docId,
    required pdfx.PdfDocument doc,
    required int index,
    required Map<int, Uint8List> pageCache,
    required int renderMaxEdge,
    Map<int, int>? resolution,
    Map<int, double>? aspects,
    Map<int, double>? pageHeights,
    required bool Function() stillCurrent,
  }) {
    final previous = _docChain[docId] ?? Future<void>.value();
    final flight = previous.catchError((Object _) {}).then((_) async {
      if (_freshEnough(pageCache, resolution, index, renderMaxEdge)) return;
      if (!stillCurrent()) return;
      await _render(
        doc: doc,
        index: index,
        pageCache: pageCache,
        renderMaxEdge: renderMaxEdge,
        resolution: resolution,
        aspects: aspects,
        pageHeights: pageHeights,
        stillCurrent: stillCurrent,
      );
    });
    _docChain[docId] = flight;
    return flight.whenComplete(() {
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
    Map<int, double>? aspects,
    Map<int, double>? pageHeights,
    bool Function()? stillCurrent,
  }) async {
    final page = await doc.getPage(index + 1);
    try {
      if (stillCurrent != null && !stillCurrent()) return;
      if (aspects != null && page.width > 0 && page.height > 0) {
        aspects.putIfAbsent(index, () => page.width / page.height);
      }
      if (pageHeights != null && page.height > 0) {
        pageHeights.putIfAbsent(index, () => page.height);
      }
      final planned = planPageRenderSize(
        pageWidth: page.width,
        pageHeight: page.height,
        renderMaxEdge: renderMaxEdge,
      );

      final rendered = await page.render(
        width: planned.width,
        height: planned.height,
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      if (stillCurrent != null && !stillCurrent()) return;
      if (rendered == null || rendered.bytes.isEmpty) return;
      if (!PageCachePolicy.shouldStore(
        cachedEdge: resolution?[index],
        renderedEdge: planned.edge,
      )) {
        return;
      }
      pageCache[index] = rendered.bytes;
      if (resolution != null) resolution[index] = planned.edge;
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

class _RenderSlot {
  final RenderRequestGates gates = RenderRequestGates();
  Future<void>? flight;
}
