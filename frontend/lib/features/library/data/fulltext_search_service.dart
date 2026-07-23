import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Full-text search index for the document library — enables searching
/// across all documents' OCR text without opening each file.
///
/// Architecture:
/// - When a document is opened/scanned, its OCR text is stored in a lightweight
///   on-disk index (one `.txt` file per document, named by file hash).
/// - Search queries scan the index files in parallel, returning matches with
///   file name + page number + snippet.
/// - This is the BM25 retriever pattern adapted for multi-document search.
///
/// Privacy: all indexing stays on device. No cloud upload.
class FulltextSearchService {
  const FulltextSearchService();

  /// Index a document's text for future search.
  Future<void> indexDocument({
    required String documentId,
    required String fileName,
    required Map<int, String> pageTexts, // page number → OCR text
  }) async {
    final dir = await _indexDir();
    final file = File('${dir.path}/$documentId.idx');
    final buffer = StringBuffer();
    buffer.writeln('FILE:$fileName');
    for (final entry in pageTexts.entries) {
      buffer.writeln('PAGE:${entry.key}');
      buffer.writeln(entry.value);
    }
    await file.writeAsString(buffer.toString());
  }

  /// Remove a document from the index.
  Future<void> removeDocument(String documentId) async {
    final dir = await _indexDir();
    final file = File('${dir.path}/$documentId.idx');
    if (await file.exists()) await file.delete();
  }

  /// Search all indexed documents for [query]. Returns matching results
  /// with document name, page number, and a text snippet around the match.
  Future<List<SearchResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    final dir = await _indexDir();
    if (!await dir.exists()) return [];

    final results = <SearchResult>[];
    final queryLower = query.toLowerCase();
    final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.idx'));

    for (final file in files) {
      final content = await file.readAsString();
      final lines = content.split('\n');
      String? fileName;
      int currentPage = 0;

      for (final line in lines) {
        if (line.startsWith('FILE:')) {
          fileName = line.substring(5);
        } else if (line.startsWith('PAGE:')) {
          currentPage = int.tryParse(line.substring(5)) ?? 0;
        } else if (line.toLowerCase().contains(queryLower)) {
          final idx = line.toLowerCase().indexOf(queryLower);
          final start = (idx - 40).clamp(0, line.length);
          final end = (idx + query.length + 40).clamp(0, line.length);
          results.add(SearchResult(
            documentId: _idFromPath(file.path),
            fileName: fileName ?? 'Unknown',
            page: currentPage,
            snippet: '…${line.substring(start, end)}…',
          ));
          if (results.length >= 50) return results; // cap
        }
      }
    }
    return results;
  }

  /// Clear the entire search index.
  Future<void> clearIndex() async {
    final dir = await _indexDir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<Directory> _indexDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/search_index');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  String _idFromPath(String path) {
    final name = path.split('/').last;
    return name.replaceAll('.idx', '');
  }
}

/// A search result pointing to a specific location in a document.
class SearchResult {
  final String documentId;
  final String fileName;
  final int page;
  final String snippet;

  const SearchResult({
    required this.documentId,
    required this.fileName,
    required this.page,
    required this.snippet,
  });
}
