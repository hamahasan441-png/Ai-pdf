/// The kind of change a [DiffSegment] represents (Phase 16).
enum DiffKind {
  /// Present in both documents (context).
  unchanged,

  /// Present only in the new document (added).
  added,

  /// Present only in the old document (removed).
  removed,
}

/// One contiguous unit of a diff — a single line (line mode) or token
/// (word mode) tagged with how it changed.
class DiffSegment {
  final DiffKind kind;
  final String text;

  const DiffSegment(this.kind, this.text);

  @override
  bool operator ==(Object other) =>
      other is DiffSegment && other.kind == kind && other.text == text;

  @override
  int get hashCode => Object.hash(kind, text);

  @override
  String toString() {
    final sign = kind == DiffKind.added
        ? '+'
        : kind == DiffKind.removed
            ? '-'
            : ' ';
    return '$sign$text';
  }
}

/// Summary counts for a diff.
class DiffStats {
  final int added;
  final int removed;
  final int unchanged;

  const DiffStats({
    required this.added,
    required this.removed,
    required this.unchanged,
  });

  /// True when the two documents are textually identical.
  bool get identical => added == 0 && removed == 0;
}

/// Compares two documents' extracted text and reports the differences
/// (Phase 16) — the engine behind a "compare versions" view.
///
/// Uses a classic longest-common-subsequence (LCS) diff so the output keeps
/// the true reading order and marks each unit as unchanged / added / removed.
/// Two granularities are offered:
///
/// - [diffLines] : paragraph/line level (fast, ideal for whole documents).
/// - [diffWords] : token level within a pair of strings (for a changed line).
///
/// Pure Dart, no Flutter dependency → fully unit-testable and isolate-safe.
class DocumentDiffService {
  const DocumentDiffService();

  /// Line-level diff of two documents.
  ///
  /// Blank lines are dropped and each line is trimmed before comparison so
  /// cosmetic whitespace differences don't create noise.
  List<DiffSegment> diffLines(String oldText, String newText) {
    return _diff(_lines(oldText), _lines(newText));
  }

  /// Word-level diff of two strings (e.g. a single changed paragraph).
  List<DiffSegment> diffWords(String oldText, String newText) {
    return _diff(_words(oldText), _words(newText));
  }

  /// Counts of added / removed / unchanged segments.
  DiffStats stats(List<DiffSegment> segments) {
    var a = 0, r = 0, u = 0;
    for (final s in segments) {
      switch (s.kind) {
        case DiffKind.added:
          a++;
          break;
        case DiffKind.removed:
          r++;
          break;
        case DiffKind.unchanged:
          u++;
          break;
      }
    }
    return DiffStats(added: a, removed: r, unchanged: u);
  }

  // --- internals -----------------------------------------------------------

  List<String> _lines(String text) => text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  List<String> _words(String text) => text
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  /// LCS diff over two token lists, emitting segments in reading order.
  List<DiffSegment> _diff(List<String> a, List<String> b) {
    final n = a.length;
    final m = b.length;

    // dp[i][j] = LCS length of a[i:] and b[j:].
    final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        if (a[i] == b[j]) {
          dp[i][j] = dp[i + 1][j + 1] + 1;
        } else {
          dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
        }
      }
    }

    final out = <DiffSegment>[];
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (a[i] == b[j]) {
        out.add(DiffSegment(DiffKind.unchanged, a[i]));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        out.add(DiffSegment(DiffKind.removed, a[i]));
        i++;
      } else {
        out.add(DiffSegment(DiffKind.added, b[j]));
        j++;
      }
    }
    while (i < n) {
      out.add(DiffSegment(DiffKind.removed, a[i++]));
    }
    while (j < m) {
      out.add(DiffSegment(DiffKind.added, b[j++]));
    }
    return out;
  }
}
