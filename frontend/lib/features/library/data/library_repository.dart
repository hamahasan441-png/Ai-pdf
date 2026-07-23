import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_pdf/features/library/domain/entities/library_folder.dart';
import 'package:ai_pdf/features/library/domain/entities/library_item.dart';

/// Persistence layer for the document library.
///
/// Uses SharedPreferences for the metadata catalog (JSON-serialized lists) and
/// the filesystem for the actual document files. This is the right trade-off
/// for a mobile app with typically <1000 items: fast startup, no SQL dep, and
/// trivial backup/restore.
///
/// For v2, if catalog size becomes a concern, we migrate to drift/sqflite with
/// a trivial schema (the toJson/fromJson is already defined).
class LibraryRepository {
  const LibraryRepository();

  static const _itemsKey = 'library_items_v1';
  static const _foldersKey = 'library_folders_v1';

  // ── Items ───────────────────────────────────────────────────────────────

  Future<List<LibraryItem>> loadItems() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_itemsKey);
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return [
        for (final j in list) LibraryItem.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveItems(List<LibraryItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode([for (final i in items) i.toJson()]);
    await prefs.setString(_itemsKey, json);
  }

  // ── Folders ─────────────────────────────────────────────────────────────

  Future<List<LibraryFolder>> loadFolders() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_foldersKey);
    if (json == null || json.isEmpty) return [];
    try {
      final list = jsonDecode(json) as List;
      return [
        for (final j in list)
          LibraryFolder.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> saveFolders(List<LibraryFolder> folders) async {
    final prefs = await SharedPreferences.getInstance();
    final json = jsonEncode([for (final f in folders) f.toJson()]);
    await prefs.setString(_foldersKey, json);
  }

  // ── File operations ─────────────────────────────────────────────────────

  /// Get the library storage directory (documents/library/).
  Future<Directory> get libraryDir async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/library');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Import a file into the library directory. Returns the new path.
  Future<String> importFile(String sourcePath) async {
    final dir = await libraryDir;
    final name = sourcePath.split('/').last;
    final dest = '${dir.path}/$name';
    // If a file with the same name exists, add a timestamp suffix.
    final f = File(sourcePath);
    if (await File(dest).exists()) {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ext = name.contains('.') ? '.${name.split('.').last}' : '';
      final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
      final newDest = '${dir.path}/${base}_$ts$ext';
      await f.copy(newDest);
      return newDest;
    }
    await f.copy(dest);
    return dest;
  }

  /// Delete a file from the library directory.
  Future<void> deleteFile(String path) async {
    final f = File(path);
    if (await f.exists()) await f.delete();
  }

  /// Get file size in bytes.
  Future<int> fileSize(String path) async {
    final f = File(path);
    if (await f.exists()) return await f.length();
    return 0;
  }
}
