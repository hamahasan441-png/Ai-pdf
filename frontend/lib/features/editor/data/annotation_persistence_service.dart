import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/data/document_identity.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Result of reading a saved annotation file.
class AnnotationLoadResult {
  final Map<int, PageLayer> layers;

  /// The file was unreadable. Its bytes were moved aside and were not
  /// treated as an empty document.
  final bool corrupt;

  /// The file is healthy but was written by a newer schema. Nothing was
  /// loaded and the file was NOT quarantined: a newer app version can still
  /// read it, so moving it aside would destroy the user's work.
  final int? unsupportedVersion;

  /// Page order and rotations the marks belong to. Null for files saved
  /// before structure was recorded, or when nothing was saved.
  final SavedPageStructure? structure;

  /// Edited form-field values, by field name.
  final Map<String, Object> formValues;

  const AnnotationLoadResult({
    required this.layers,
    this.corrupt = false,
    this.unsupportedVersion,
    this.structure,
    this.formValues = const {},
  });
}

/// Persists editor annotations to disk so work is never lost.
///
/// Saves go to `<appDocs>/annotations/<stable-id>.json`. The id is a
/// deterministic hash of the source path, not [String.hashCode].
class AnnotationPersistenceService {
  final Future<Directory> Function()? documentsDirectory;

  const AnnotationPersistenceService({this.documentsDirectory});

  /// Save all annotation layers for the document at [filePath].
  ///
  /// Writes a temporary file and renames it into place so a crash mid-write
  /// cannot leave a half-written JSON as the only copy.
  Future<void> save({
    required String filePath,
    required Map<int, PageLayer> layers,
    SavedPageStructure? structure,
    Map<String, Object> formValues = const {},
  }) async {
    final savePath = await _savePath(filePath);
    final content = jsonEncode(layersToJson(layers, structure: structure, formValues: formValues));
    final tmp = File('$savePath.tmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(savePath);
  }

  /// Load saved annotations. Prefer [loadChecked] when a corrupt file must
  /// be distinguished from a document that simply has no marks.
  Future<Map<int, PageLayer>> load(String filePath) async {
    final result = await loadChecked(filePath);
    return result.layers;
  }

  Future<AnnotationLoadResult> loadChecked(String filePath) async {
    final savePath = await _savePath(filePath);
    await _migrateLegacy(filePath, savePath);
    final file = File(savePath);
    if (!file.existsSync()) {
      return const AnnotationLoadResult(layers: {});
    }
    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content);
      if (decoded is! Map) {
        throw const FormatException('annotation file is not a JSON object');
      }
      final json = Map<String, dynamic>.from(decoded);
      final version = json['version'];
      if (version is int && version > 1) {
        // A future schema is not corruption. Keep the file exactly where it
        // is so an updated app can still restore the user's marks; report
        // the version so the UI can say so instead of claiming the file was
        // unreadable.
        return AnnotationLoadResult(layers: {}, unsupportedVersion: version);
      }
      if (version != 1) {
        throw FormatException('unsupported annotation schema: $version');
      }
      final structure = json.containsKey('structure')
          ? SavedPageStructure.fromJson(json['structure'])
          : null;
      if (json.containsKey('structure') && structure == null) {
        throw const FormatException('malformed page structure');
      }
      return AnnotationLoadResult(
        layers: layersFromJson(json),
        structure: structure,
        formValues: formValuesFromJson(json['forms']),
      );
    } catch (_) {
      final backup = File('$savePath.corrupt');
      if (backup.existsSync()) {
        backup.deleteSync();
      }
      await file.rename(backup.path);
      return const AnnotationLoadResult(layers: {}, corrupt: true);
    }
  }

  /// Move the save file aside without reading it again. Used when its marks
  /// do not fit the document that was opened (for example the PDF at that
  /// path was replaced by one with fewer pages).
  Future<void> quarantine(String filePath) async {
    final savePath = await _savePath(filePath);
    final file = File(savePath);
    if (!file.existsSync()) return;
    final backup = File('$savePath.corrupt');
    if (backup.existsSync()) backup.deleteSync();
    await file.rename(backup.path);
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

  Future<void> _migrateLegacy(String filePath, String savePath) async {
    final current = File(savePath);
    if (current.existsSync()) return;
    final legacyName = filePath.hashCode.toRadixString(36);
    final legacy = File('${current.parent.path}/$legacyName.json');
    if (!legacy.existsSync()) return;
    try {
      await legacy.rename(savePath);
    } catch (_) {
      // Leave the old file in place if it cannot be moved.
    }
  }

  Future<String> _savePath(String filePath) async {
    final dir = documentsDirectory != null
        ? await documentsDirectory!()
        : await getApplicationDocumentsDirectory();
    final saveDir = Directory('${dir.path}/annotations');
    if (!saveDir.existsSync()) {
      saveDir.createSync(recursive: true);
    }
    return '${saveDir.path}/${stableDocumentId(filePath)}.json';
  }
}
