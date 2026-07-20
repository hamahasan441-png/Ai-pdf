import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Persists annotation layers to a JSON file on disk.
///
/// ### Crash Recovery
/// Auto-save is called after each command so work is never lost.
/// On re-open, [loadAnnotations] restores the editing session.
///
/// ### File format
/// ```json
/// {
///   "version": 1,
///   "fileHash": "abc123...",
///   "pageCount": 5,
///   "pages": {
///     "0": [/* annotation json objects */],
///     "1": []
///   }
/// }
/// ```
class AnnotationPersistenceService {
  const AnnotationPersistenceService();

  static const int _version = 1;

  /// Get the on-disk path for a given source file (keyed by its basename hash).
  Future<String> _pathFor(String fileHash) async {
    final dir = await getApplicationDocumentsDirectory();
    final sub = Directory('${dir.path}/annotations');
    if (!sub.existsSync()) {
      sub.createSync(recursive: true);
    }
    return '${sub.path}/$fileHash.json';
  }

  /// Save all annotation layers for a document.
  Future<void> saveAnnotations({
    required String fileHash,
    required int pageCount,
    required Map<int, PageLayer> layers,
  }) async {
    final path = await _pathFor(fileHash);
    final data = <String, dynamic>{
      'version': _version,
      'fileHash': fileHash,
      'pageCount': pageCount,
      'savedAt': DateTime.now().toIso8601String(),
      'pages': <String, dynamic>{},
    };
    for (final entry in layers.entries) {
      final pageKey = entry.key.toString();
      data['pages'][pageKey] = entry.value.toJson();
    }
    await File(path).writeAsString(jsonEncode(data));
  }

  /// Load saved annotations for a document. Returns null if no save exists.
  Future<Map<int, PageLayer>?> loadAnnotations(String fileHash) async {
    final path = await _pathFor(fileHash);
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final content = await file.readAsString();
      final data = jsonDecode(content) as Map<String, dynamic>;
      if ((data['version'] as int? ?? 0) != _version) return null;

      final pagesRaw = data['pages'] as Map<String, dynamic>? ?? {};
      final layers = <int, PageLayer>{};
      for (final entry in pagesRaw.entries) {
        final pageIndex = int.tryParse(entry.key) ?? 0;
        final items = entry.value as List<dynamic>? ?? [];
        final layer = PageLayer();
        for (final item in items) {
          if (item is Map<String, dynamic>) {
            try {
              layer.add(annotationFromJson(item));
            } catch (_) {
              // Skip corrupt entries — never crash on load.
            }
          }
        }
        layers[pageIndex] = layer;
      }
      return layers;
    } catch (_) {
      return null;
    }
  }

  /// Delete saved annotations for a document (e.g. after successful export).
  Future<void> deleteAnnotations(String fileHash) async {
    final path = await _pathFor(fileHash);
    final file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Compute a fast hash for a file path (used as the save-file key).
  /// Uses the basename + file size as a lightweight fingerprint.
  Future<String> computeFileHash(String filePath) async {
    final file = File(filePath);
    final name = file.uri.pathSegments.last;
    final size = file.existsSync() ? await file.length() : 0;
    return '${name.hashCode.toRadixString(36)}_$size';
  }
}
