/// Parses and formats human page-range specs for extract / split / delete /
/// print operations (Phase 18).
///
/// Users type ranges the natural way — **1‑based**, e.g. `"1-3, 5, 8-10"` — and
/// this service converts them to validated, de‑duplicated, ascending
/// **0‑based** page indices the editor works in. It also does the reverse
/// ([format]) and set operations ([invert]) so a "delete these pages" spec can
/// become a "keep the rest" list.
///
/// Pure Dart, no Flutter dependency → fully unit‑testable.
class PageRangeService {
  const PageRangeService();

  /// Parse a 1‑based [spec] against a document of [pageCount] pages into sorted,
  /// unique 0‑based indices.
  ///
  /// - Whitespace is ignored. `"1 - 3 , 5"` is accepted.
  /// - Reversed ranges (`"3-1"`) are normalised to `1..3`.
  /// - An empty/whitespace spec yields an empty list.
  /// - Throws [FormatException] on a malformed token or an index outside
  ///   `1..pageCount`.
  List<int> parse(String spec, int pageCount) {
    final indices = <int>{};
    final trimmed = spec.trim();
    if (trimmed.isEmpty) return <int>[];

    for (final rawToken in trimmed.split(',')) {
      final token = rawToken.trim();
      if (token.isEmpty) continue; // tolerate "1,,2" and trailing commas

      final dash = token.indexOf('-');
      if (dash < 0) {
        indices.add(_parseOne(token, pageCount));
      } else {
        final loStr = token.substring(0, dash).trim();
        final hiStr = token.substring(dash + 1).trim();
        var lo = _parseOne(loStr, pageCount);
        var hi = _parseOne(hiStr, pageCount);
        if (lo > hi) {
          final t = lo;
          lo = hi;
          hi = t;
        }
        for (var i = lo; i <= hi; i++) {
          indices.add(i);
        }
      }
    }

    final sorted = indices.toList()..sort();
    return sorted;
  }

  /// Like [parse] but returns null instead of throwing on invalid input.
  List<int>? tryParse(String spec, int pageCount) {
    try {
      return parse(spec, pageCount);
    } on FormatException {
      return null;
    }
  }

  /// Format sorted 0‑based [indices] back into a compact 1‑based spec such as
  /// `"1-3, 5, 8-10"`. Input need not be pre‑sorted or unique.
  String format(Iterable<int> indices) {
    final sorted = indices.toSet().toList()..sort();
    if (sorted.isEmpty) return '';

    final parts = <String>[];
    var start = sorted.first;
    var prev = sorted.first;

    void flush(int end) {
      if (start == end) {
        parts.add('${start + 1}');
      } else {
        parts.add('${start + 1}-${end + 1}');
      }
    }

    for (var i = 1; i < sorted.length; i++) {
      final cur = sorted[i];
      if (cur == prev + 1) {
        prev = cur;
        continue;
      }
      flush(prev);
      start = cur;
      prev = cur;
    }
    flush(prev);
    return parts.join(', ');
  }

  /// The complement of [indices] within `0..pageCount-1` (e.g. pages to keep
  /// when [indices] are the pages to delete), ascending.
  List<int> invert(Iterable<int> indices, int pageCount) {
    final set = indices.toSet();
    final out = <int>[];
    for (var i = 0; i < pageCount; i++) {
      if (!set.contains(i)) out.add(i);
    }
    return out;
  }

  int _parseOne(String s, int pageCount) {
    final n = int.tryParse(s);
    if (n == null) {
      throw FormatException('Not a page number: "$s"');
    }
    if (n < 1 || n > pageCount) {
      throw FormatException('Page $n out of range (1..$pageCount)');
    }
    return n - 1; // to 0-based
  }
}
