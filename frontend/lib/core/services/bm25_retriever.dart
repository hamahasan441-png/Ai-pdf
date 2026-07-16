import 'dart:math' as math;

/// One retrieved passage with the page it came from and its relevance score.
class RetrievedChunk {
  final int page;
  final String text;
  final double score;
  const RetrievedChunk(this.page, this.text, this.score);
}

/// A tiny, dependency-free BM25 (Okapi) lexical retriever that runs fully
/// on-device. Given the OCR'd text of each page, it indexes short chunks and
/// ranks them against a query so the AI can be grounded on the most relevant
/// passages — and cite the pages they came from.
///
/// BM25 is deliberately lexical (keyword) rather than neural: it needs no model
/// download, is instant on a phone, and is especially strong for the queries
/// that matter in documents — names, dates, amounts, IDs and error codes.
class Bm25Retriever {
  final List<_Chunk> _chunks = [];
  final Map<String, int> _docFreq = {};
  double _avgLen = 0;

  static const double _k1 = 1.5;
  static const double _b = 0.75;

  bool get isEmpty => _chunks.isEmpty;
  int get chunkCount => _chunks.length;

  void clear() {
    _chunks.clear();
    _docFreq.clear();
    _avgLen = 0;
  }

  /// Build the index from page (1-based) -> full page text.
  void index(Map<int, String> pageText, {int maxCharsPerChunk = 700}) {
    clear();
    pageText.forEach((page, text) {
      for (final chunk in _splitIntoChunks(text, maxCharsPerChunk)) {
        final tokens = _tokenize(chunk);
        if (tokens.isEmpty) continue;
        final tf = <String, int>{};
        for (final t in tokens) {
          tf[t] = (tf[t] ?? 0) + 1;
        }
        _chunks.add(_Chunk(page, chunk, tokens.length, tf));
        for (final term in tf.keys) {
          _docFreq[term] = (_docFreq[term] ?? 0) + 1;
        }
      }
    });
    if (_chunks.isEmpty) {
      _avgLen = 0;
      return;
    }
    final totalLen = _chunks.fold<int>(0, (a, c) => a + c.length);
    _avgLen = totalLen / _chunks.length;
  }

  /// Return the top [topK] chunks most relevant to [query], best first.
  List<RetrievedChunk> search(String query, {int topK = 5}) {
    if (_chunks.isEmpty) return const [];
    final queryTerms = _tokenize(query).toSet();
    if (queryTerms.isEmpty) return const [];
    final n = _chunks.length;
    final avg = _avgLen == 0 ? 1.0 : _avgLen;

    final scored = <RetrievedChunk>[];
    for (final c in _chunks) {
      double score = 0;
      for (final term in queryTerms) {
        final tf = c.termFreq[term];
        if (tf == null) continue;
        final df = _docFreq[term] ?? 0;
        if (df == 0) continue;
        final idf = math.log(1 + (n - df + 0.5) / (df + 0.5));
        final denom = tf + _k1 * (1 - _b + _b * (c.length / avg));
        score += idf * (tf * (_k1 + 1)) / denom;
      }
      if (score > 0) scored.add(RetrievedChunk(c.page, c.text, score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.length > topK ? scored.sublist(0, topK) : scored;
  }

  List<String> _splitIntoChunks(String text, int maxChars) {
    final t = text.trim();
    if (t.isEmpty) return const [];
    if (t.length <= maxChars) return [t];
    final out = <String>[];
    final parts = t.split(RegExp(r'(?<=[.!?\n])\s+'));
    final buf = StringBuffer();
    for (final p in parts) {
      if (buf.isNotEmpty && buf.length + p.length > maxChars) {
        out.add(buf.toString().trim());
        buf.clear();
      }
      buf.write(p);
      buf.write(' ');
    }
    final tail = buf.toString().trim();
    if (tail.isNotEmpty) out.add(tail);
    return out;
  }

  static const Set<String> _stopWords = {
    'the', 'a', 'an', 'and', 'or', 'of', 'to', 'in', 'on', 'for', 'is', 'are',
    'was', 'were', 'be', 'been', 'with', 'as', 'at', 'by', 'it', 'its', 'this',
    'that', 'these', 'those', 'from', 'you', 'your', 'i', 'we', 'they', 'he',
    'she', 'do', 'does', 'did', 'has', 'have', 'had', 'will', 'would', 'can',
    'could', 'should', 'my', 'me', 'our', 'us', 'if', 'then', 'so', 'but',
  };

  List<String> _tokenize(String s) {
    final matches = RegExp(r'[a-z0-9]+').allMatches(s.toLowerCase());
    final out = <String>[];
    for (final m in matches) {
      final w = m.group(0)!;
      if (w.length < 2) continue;
      if (_stopWords.contains(w)) continue;
      out.add(w);
    }
    return out;
  }
}

class _Chunk {
  final int page;
  final String text;
  final int length; // token count
  final Map<String, int> termFreq;
  const _Chunk(this.page, this.text, this.length, this.termFreq);
}
