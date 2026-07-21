import 'dart:typed_data';

import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Service for reordering, inserting, and removing pages within the editor.
///
/// Enables in-editor page management (drag to reorder, delete a page, insert
/// a blank page) without leaving the editor screen. Operates on the in-memory
/// page cache and layer maps — the reordered document is exported via the
/// normal export pipeline.
class PageReorderService {
  const PageReorderService();

  /// Move a page from [fromIndex] to [toIndex].
  /// Updates both the page cache and annotation layers.
  void movePage({
    required int fromIndex,
    required int toIndex,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
    required int pageCount,
  }) {
    if (fromIndex == toIndex) return;
    if (fromIndex < 0 || fromIndex >= pageCount) return;
    if (toIndex < 0 || toIndex >= pageCount) return;

    // Rebuild both maps with the new ordering.
    final orderedCache = _reorderMap(pageCache, fromIndex, toIndex, pageCount);
    final orderedLayers = _reorderMap(layers, fromIndex, toIndex, pageCount);

    pageCache
      ..clear()
      ..addAll(orderedCache);
    layers
      ..clear()
      ..addAll(orderedLayers);
  }

  /// Delete a page at [index]. Returns the new page count.
  int deletePage({
    required int index,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
    required int pageCount,
  }) {
    if (pageCount <= 1) return pageCount; // can't delete the last page
    if (index < 0 || index >= pageCount) return pageCount;

    // Remove the page and shift subsequent pages down.
    pageCache.remove(index);
    layers.remove(index);

    final newCache = <int, Uint8List>{};
    final newLayers = <int, PageLayer>{};
    for (var i = 0; i < pageCount; i++) {
      if (i == index) continue;
      final newIdx = i < index ? i : i - 1;
      if (pageCache.containsKey(i)) newCache[newIdx] = pageCache[i]!;
      if (layers.containsKey(i)) newLayers[newIdx] = layers[i]!;
    }

    pageCache
      ..clear()
      ..addAll(newCache);
    layers
      ..clear()
      ..addAll(newLayers);

    return pageCount - 1;
  }

  /// Insert a blank page at [index]. Returns the new page count.
  int insertBlankPage({
    required int index,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
    required int pageCount,
  }) {
    // Shift existing pages from [index] onward up by one.
    final newCache = <int, Uint8List>{};
    final newLayers = <int, PageLayer>{};

    for (var i = pageCount - 1; i >= index; i--) {
      if (pageCache.containsKey(i)) newCache[i + 1] = pageCache[i]!;
      if (layers.containsKey(i)) newLayers[i + 1] = layers[i]!;
      pageCache.remove(i);
      layers.remove(i);
    }

    pageCache.addAll(newCache);
    layers.addAll(newLayers);
    // The blank page at [index] has no cache entry (will show as empty/white).
    layers[index] = PageLayer();

    return pageCount + 1;
  }

  /// Duplicate a page at [index]. Returns the new page count.
  int duplicatePage({
    required int index,
    required Map<int, Uint8List> pageCache,
    required Map<int, PageLayer> layers,
    required int pageCount,
  }) {
    final newCount = insertBlankPage(
      index: index + 1,
      pageCache: pageCache,
      layers: layers,
      pageCount: pageCount,
    );
    // Copy the rendered bytes to the new slot.
    if (pageCache.containsKey(index)) {
      pageCache[index + 1] = Uint8List.fromList(pageCache[index]!);
    }
    return newCount;
  }

  Map<int, T> _reorderMap<T>(Map<int, T> source, int from, int to, int count) {
    final keys = List.generate(count, (i) => i);
    final item = keys.removeAt(from);
    keys.insert(to, item);
    final result = <int, T>{};
    for (var newIdx = 0; newIdx < keys.length; newIdx++) {
      final oldIdx = keys[newIdx];
      if (source.containsKey(oldIdx)) {
        result[newIdx] = source[oldIdx] as T;
      }
    }
    return result;
  }
}
