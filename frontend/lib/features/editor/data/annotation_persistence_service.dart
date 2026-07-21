import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';

/// Persists editor annotations to disk so work is never lost.
///
/// ### How it works
/// - After each edit (via [save]), the full layer state is serialized to JSON
///   and written to a file keyed by the source document's path hash.
/// - On re-open (via [load]), saved annotations are restored into the editor's
///   layer map — the user picks up exactly where they left off.
/// - On successful export (via [delete]), the save file is removed (the work
///   is now in the exported PDF).
///
/// ### Crash recovery
/// Because [save] is called after every mutation (debounce-friendly from the
/// caller), an unexpected kill/crash loses at most the last in-flight edit.
///
/// ### File location
/// Saves go to `<appDocs>/annotations/<hash>.json`. This directory is internal
/// to the app (not visible in the gallery or file manager), automatically
/// cleaned on uninstall, and never backed up (per the security config).
class AnnotationPersistenceService {
  const AnnotationPersistenceService();

  /// Save all annotation layers for the document at [filePath].
  Future<void> save({
    required String filePath,
    required Map<int, PageLayer> layers,
  }) async {
    final savePath = await _savePath(filePath);
    final json = layersToJson(layers);
    final content = jsonEncode(json);
    await File(savePath).writeAsString(content);
  }

  /// Load saved annotations for the document at [filePath].
  /// Returns an empty map if no save exists or it's corrupt.
  Future<Map<int, PageLayer>> load(String filePath) async {
    final savePath = await _savePath(filePath);
    final file = File(savePath);
    if (!file.existsSync()) return {};
    try {
      final content = await file.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return layersFromJson(json);
    } catch (_) {
      // Corrupt file — don't block the editor. The user starts fresh.
      return {};
    }
  }

  /// Check whether a save file exists for [filePath].
  Future<bool> hasSavedState(String filePath) async {
    final savePath = await _savePath(filePath);
    return File(savePath).existsSync();
  }

  /// Delete the save file (called after successful export).
  Future<void> delete(String filePath) async {
    final savePath = await _savePath(filePath);
    final file = File(savePath);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// Compute the on-disk path for a given source file.
  Future<String> _savePath(String filePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final saveDir = Directory('${dir.path}/annotations');
    if (!saveDir.existsSync()) {
      saveDir.createSync(recursive: true);
    }
    final hash = filePath.hashCode.toRadixString(36);
    return '${saveDir.path}/$hash.json';
  }
}
