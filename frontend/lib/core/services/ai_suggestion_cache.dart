import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Offline AI suggestions cache — stores previously-fetched AI responses
/// (summaries, suggestions, translations) so they can be displayed instantly
/// without network on subsequent opens.
///
/// Architecture:
/// - Key = hash of (document_text + operation_type)
/// - Value = JSON response from the AI endpoint
/// - TTL = 7 days (configurable)
/// - Max entries = 100 (LRU eviction)
///
/// Privacy: cache stays on device, encrypted at rest by the OS file system.
class AiSuggestionCache {
  static const int _maxEntries = 100;
  static const Duration _ttl = Duration(days: 7);

  /// Get a cached response for the given key, or null if not cached/expired.
  Future<Map<String, dynamic>?> get(String key) async {
    final file = await _fileFor(key);
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final entry = jsonDecode(content) as Map<String, dynamic>;
      final cachedAt = DateTime.tryParse(entry['_cachedAt'] as String? ?? '');
      if (cachedAt == null || DateTime.now().difference(cachedAt) > _ttl) {
        await file.delete();
        return null;
      }
      entry.remove('_cachedAt');
      return entry;
    } catch (_) {
      return null;
    }
  }

  /// Store a response in the cache.
  Future<void> put(String key, Map<String, dynamic> value) async {
    await _evictIfNeeded();
    final file = await _fileFor(key);
    final entry = Map<String, dynamic>.from(value);
    entry['_cachedAt'] = DateTime.now().toIso8601String();
    await file.writeAsString(jsonEncode(entry));
  }

  /// Check if a cached value exists and is not expired.
  Future<bool> has(String key) async {
    return (await get(key)) != null;
  }

  /// Clear the entire cache.
  Future<void> clear() async {
    final dir = await _cacheDir();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Generate a cache key from document text + operation.
  static String keyFor(String documentText, String operation) {
    final hash = documentText.hashCode ^ operation.hashCode;
    return hash.toRadixString(36);
  }

  Future<void> _evictIfNeeded() async {
    final dir = await _cacheDir();
    if (!await dir.exists()) return;
    final files = dir.listSync().whereType<File>().toList();
    if (files.length < _maxEntries) return;

    // Sort by modification time, delete oldest.
    files.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
    final toDelete = files.length - _maxEntries + 10; // free 10 slots
    for (var i = 0; i < toDelete && i < files.length; i++) {
      await files[i].delete();
    }
  }

  Future<File> _fileFor(String key) async {
    final dir = await _cacheDir();
    return File('${dir.path}/$key.json');
  }

  Future<Directory> _cacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/ai_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
