/// Which original PDF page each editor slot came from.
///
/// -1 is a blank page that is not in the source file. Export must use this
/// list. The visual index is not the PDF page number after a delete or insert.
class PageSourceMap {
  final List<int> sources;

  PageSourceMap(int count) : sources = [for (var i = 0; i < count; i++) i];

  int get length => sources.length;

  void removeAt(int index) {
    if (sources.length <= 1) return;
    if (index < 0 || index >= sources.length) return;
    sources.removeAt(index);
  }

  void insertBlank(int index) {
    final at = index.clamp(0, sources.length);
    sources.insert(at, -1);
  }

  void duplicate(int index) {
    if (index < 0 || index >= sources.length) return;
    sources.insert(index + 1, sources[index]);
  }

  /// Shift map entries the same way a page delete shifts the editor.
  static Map<int, T> afterDelete<T>(Map<int, T> map, int index, int oldCount) {
    final next = <int, T>{};
    for (var i = 0; i < oldCount; i++) {
      if (i == index || !map.containsKey(i)) continue;
      next[i < index ? i : i - 1] = map[i] as T;
    }
    return next;
  }

  /// Shift map entries the same way a page insert shifts the editor.
  static Map<int, T> afterInsert<T>(Map<int, T> map, int index, int oldCount) {
    final next = <int, T>{};
    for (var i = 0; i < oldCount; i++) {
      if (!map.containsKey(i)) continue;
      next[i < index ? i : i + 1] = map[i] as T;
    }
    return next;
  }
}

/// Editor slots to write. [only] limits export to those pages.
List<int> exportSlots({required int pageCount, List<int>? only}) {
  if (only == null) return [for (var i = 0; i < pageCount; i++) i];
  final seen = <int>{};
  final slots = <int>[];
  for (final i in only) {
    if (i < 0 || i >= pageCount || !seen.add(i)) continue;
    slots.add(i);
  }
  return slots;
}
