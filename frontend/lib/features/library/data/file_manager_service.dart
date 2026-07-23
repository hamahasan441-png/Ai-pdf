import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// File Manager service — handles file operations for the document library:
/// rename, move, copy, delete, get info, duplicate.
///
/// All operations happen on the device's local storage.
class FileManagerService {
  const FileManagerService();

  /// Rename a document file.
  Future<String> rename(String filePath, String newName) async {
    final file = File(filePath);
    if (!await file.exists()) throw FileSystemException('File not found', filePath);
    final dir = file.parent.path;
    final ext = filePath.split('.').last;
    final newPath = '$dir/$newName.$ext';
    await file.rename(newPath);
    return newPath;
  }

  /// Move a file to a different folder.
  Future<String> move(String filePath, String destinationDir) async {
    final file = File(filePath);
    if (!await file.exists()) throw FileSystemException('File not found', filePath);
    final name = filePath.split('/').last;
    final dest = '$destinationDir/$name';
    await Directory(destinationDir).create(recursive: true);
    await file.rename(dest);
    return dest;
  }

  /// Copy a file.
  Future<String> copy(String filePath, {String? newName}) async {
    final file = File(filePath);
    if (!await file.exists()) throw FileSystemException('File not found', filePath);
    final dir = file.parent.path;
    final name = newName ?? '${_nameWithout(filePath)}_copy.${_ext(filePath)}';
    final dest = '$dir/$name';
    await file.copy(dest);
    return dest;
  }

  /// Duplicate a file (shortcut for copy with auto-naming).
  Future<String> duplicate(String filePath) async {
    return copy(filePath);
  }

  /// Delete a file permanently.
  Future<void> delete(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  /// Get file info (size, modified date, path).
  Future<FileInfo> getInfo(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) throw FileSystemException('File not found', filePath);
    final stat = await file.stat();
    return FileInfo(
      path: filePath,
      name: filePath.split('/').last,
      sizeBytes: stat.size,
      modified: stat.modified,
      created: stat.changed,
    );
  }

  /// List all PDF files in the documents directory.
  Future<List<String>> listDocuments() async {
    final dir = await getApplicationDocumentsDirectory();
    final files = dir.listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.pdf'))
        .map((f) => f.path)
        .toList();
    files.sort((a, b) => File(b).statSync().modified.compareTo(File(a).statSync().modified));
    return files;
  }

  /// Create a new folder.
  Future<String> createFolder(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/$name');
    await folder.create(recursive: true);
    return folder.path;
  }

  String _nameWithout(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  String _ext(String path) {
    final dot = path.lastIndexOf('.');
    return dot > 0 ? path.substring(dot + 1) : '';
  }
}

class FileInfo {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;
  final DateTime created;

  const FileInfo({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
    required this.created,
  });

  String get sizeFormatted {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
