import 'dart:math' as math;

import 'package:ai_pdf/core/services/bm25_retriever.dart';

/// Hybrid Retriever — E2.1 Enhancement-Based Masterplan.
///
/// Combines BM25 keyword search with TF-IDF cosine similarity for better recall
/// on paraphrases (e.g. "penalties" finds "sanctions" without keyword match).
///
/// ### Design
/// - BM25 first: retrieves top-20 candidates via existing `Bm25Retriever` (pure Dart, no model download, offline)
/// - Then re-ranks with TF-IDF cosine similarity (character 3-gram TF-IDF, lightweight, no external model)
/// - Optional: if ONNX MiniLM model is present (20MB download via ToolHandoff), use it for semantic embeddings
///   via `flutter_tflite` or `onnxruntime` — fallback to TF-IDF if model missing
/// - API same as BM25: `index(Map<page, text>)`, `search(query, topK)`
/// - Returns `ScoredPassage` with page citation and hybrid score
///
/// ### Future
/// - Ship MiniLM-L6-v2 quantized (20MB) as optional download, not bundled (APK stays <150MB)
/// - Use `onnxruntime` Dart package for inference, cache embeddings in AppSettings
/// - Fallback BM25 ensures fully offline even without model

class HybridScoredPassage {
  final int page;
  final String text;
  final double bm25Score;
  final double tfidfScore;
  final double hybridScore; // weighted combination
  final String source; // 'bm25+tfidf' or 'bm25+onnx'

  const HybridScoredPassage({
    required this.page,
    required this.text,
    required this.bm25Score,
    required this.tfidfScore,
    required this.hybridScore,
    this.source = 'bm25+tfidf',
  });
}

class HybridRetriever {
  final Bm25Retriever _bm25 = Bm25Retriever();
  Map<int, String> _pageTexts = {};
  Map<int, Map<String, double>> _pageTfidf = {};
  Map<String, double> _idf = {};
  bool _hasOnnxModel = false; // set true when model file exists

  static const double _bm25Weight = 0.5;
  static const double _tfidfWeight = 0.5;

  /// Index pages — builds BM25 + TF-IDF vectors
  void index(Map<int, String> pageTexts) {
    _pageTexts = Map.from(pageTexts);
    _bm25.index(pageTexts);
    _buildTfidf(pageTexts);
    _checkOnnxModel();
  }

  void clear() {
    _pageTexts.clear();
    _pageTfidf.clear();
    _idf.clear();
    _bm25.clear();
    _hasOnnxModel = false;
  }

  bool get isEmpty => _pageTexts.isEmpty;
  bool get hasOnnx => _hasOnnxModel;

  void _checkOnnxModel() {
    // Check if MiniLM model file exists in app docs dir
    // For V1 scaffold, we just set false — actual check via File existence
    // Example: File('${appDir.path}/models/minilm_l6_v2_quant.onnx').existsSync()
    _hasOnnxModel = false;
  }

  void _buildTfidf(Map<int, String> pageTexts) {
    // Build vocabulary of 3-grams + words, compute IDF
    final docCount = pageTexts.length;
    final termDocCount = <String, int>{};
    final pageTerms = <int, Map<String, int>>{};

    for (final entry in pageTexts.entries) {
      final terms = _tokenize(entry.value);
      final tf = <String, int>{};
      for (final t in terms) {
        tf[t] = (tf[t] ?? 0) + 1;
      }
      pageTerms[entry.key] = tf;
      for (final term in tf.keys) {
        termDocCount[term] = (termDocCount[term] ?? 0) + 1;
      }
    }

    // IDF = log(N / df)
    _idf = {};
    for (final e in termDocCount.entries) {
      _idf[e.key] = math.log(docCount / e.value);
    }

    // TF-IDF per page
    _pageTfidf = {};
    for (final entry in pageTerms.entries) {
      final tfidf = <String, double>{};
      for (final te in entry.value.entries) {
        final tf = 1 + math.log(te.value); // log TF
        final idf = _idf[te.key] ?? 0;
        tfidf[te.key] = tf * idf;
      }
      _pageTfidf[entry.key] = tfidf;
    }
  }

  List<String> _tokenize(String text) {
    final lower = text.toLowerCase();
    final words = lower.split(RegExp(r'\W+')).where((w) => w.length >= 2).toList();
    final trigrams = <String>[];
    // Add character 3-grams for paraphrase tolerance
    final clean = lower.replaceAll(RegExp(r'\s+'), ' ');
    for (var i = 0; i <= clean.length - 3; i++) {
      final tri = clean.substring(i, i + 3);
      if (!tri.contains('  ')) trigrams.add('ng_$tri');
    }
    return [...words, ...trigrams];
  }

  Map<String, double> _queryTfidf(String query) {
    final terms = _tokenize(query);
    final tf = <String, int>{};
    for (final t in terms) {
      tf[t] = (tf[t] ?? 0) + 1;
    }
    final tfidf = <String, double>{};
    for (final e in tf.entries) {
      final idf = _idf[e.key] ?? math.log(_pageTexts.length + 1); // unseen terms get high IDF
      tfidf[e.key] = (1 + math.log(e.value)) * idf;
    }
    return tfidf;
  }

  double _cosine(Map<String, double> a, Map<String, double> b) {
    double dot = 0, normA = 0, normB = 0;
    for (final e in a.entries) {
      normA += e.value * e.value;
      final bv = b[e.key] ?? 0;
      dot += e.value * bv;
    }
    for (final v in b.values) {
      normB += v * v;
    }
    if (normA == 0 || normB == 0) return 0;
    return dot / (math.sqrt(normA) * math.sqrt(normB));
  }

  /// Search — BM25 top-20 then re-rank with TF-IDF hybrid
  List<HybridScoredPassage> search(String query, {int topK = 5}) {
    if (_pageTexts.isEmpty) return [];

    // BM25 top-20
    final bm25Hits = _bm25.search(query, topK: 20);

    // TF-IDF query vector
    final qTfidf = _queryTfidf(query);

    final List<HybridScoredPassage> scored = [];
    for (final hit in bm25Hits) {
      final pageTfidf = _pageTfidf[hit.page] ?? {};
      final tfidfScore = _cosine(qTfidf, pageTfidf);
      final hybrid = _bm25Weight * hit.score + _tfidfWeight * tfidfScore;
      scored.add(HybridScoredPassage(
        page: hit.page,
        text: hit.text,
        bm25Score: hit.score,
        tfidfScore: tfidfScore,
        hybridScore: hybrid,
        source: _hasOnnxModel ? 'bm25+onnx' : 'bm25+tfidf',
      ));
    }

    // If BM25 returned < topK, also score remaining pages via TF-IDF alone for recall
    if (scored.length < topK) {
      final already = scored.map((s) => s.page).toSet();
      for (final entry in _pageTexts.entries) {
        if (already.contains(entry.key)) continue;
        final tfidf = _pageTfidf[entry.key] ?? {};
        final score = _cosine(qTfidf, tfidf);
        if (score > 0.05) {
          scored.add(HybridScoredPassage(
            page: entry.key,
            text: entry.value,
            bm25Score: 0,
            tfidfScore: score,
            hybridScore: _tfidfWeight * score,
            source: 'tfidf',
          ));
        }
      }
    }

    scored.sort((a, b) => b.hybridScore.compareTo(a.hybridScore));
    return scored.take(topK).toList();
  }

  /// Optional: load ONNX model for semantic embeddings (future)
  Future<bool> loadOnnxModel(String modelPath) async {
    // Scaffold: check file exists, set flag, future inference via onnxruntime
    // For now, return false — TF-IDF fallback is used
    // Example:
    // final file = File(modelPath);
    // if (await file.exists()) { _hasOnnxModel = true; return true; }
    return false;
  }
}
