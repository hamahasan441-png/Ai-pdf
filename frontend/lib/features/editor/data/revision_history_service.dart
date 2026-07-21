import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local revision history — persists edit commands across sessions.
///
/// Every mutation (add, remove, move, edit) is logged as a timestamped entry.
/// This enables:
/// - "Version history" UI showing what changed and when
/// - Undo across sessions (reopen file → undo changes from yesterday)
/// - Future: privacy-preserving sync (ship the log, not the document)
///
/// ### Storage
/// Each document gets a `.edits.jsonl` file (one JSON object per line).
/// Append-only (never rewritten) for crash safety.
class RevisionHistoryService {
  const RevisionHistoryService();

  /// Append an edit entry to the revision log for [filePath].
  Future<void> appendEntry({
    required String filePath,
    required String commandType,
    required String description,
    Map<String, dynamic>? metadata,
  }) async {
    final logPath = await _logPath(filePath);
    final entry = {
      'ts': DateTime.now().toIso8601String(),
      'cmd': commandType,
      'desc': description,
      if (metadata != null) 'meta': metadata,
    };
    await File(logPath).writeAsString(
      '${jsonEncode(entry)}\n',
      mode: FileMode.append,
    );
  }

  /// Load all revision entries for a document (newest first).
  Future<List<Map<String, dynamic>>> loadHistory(String filePath) async {
    final logPath = await _logPath(filePath);
    final file = File(logPath);
    if (!file.existsSync()) return [];
    try {
      final lines = await file.readAsLines();
      final entries = <Map<String, dynamic>>[];
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        try {
          entries.add(jsonDecode(line) as Map<String, dynamic>);
        } catch (_) {
          // Skip corrupt lines.
        }
      }
      return entries.reversed.toList(); // newest first
    } catch (_) {
      return [];
    }
  }

  /// Get the number of edits made to a document.
  Future<int> editCount(String filePath) async {
    final history = await loadHistory(filePath);
    return history.length;
  }

  /// Clear revision history for a document (e.g. after export / "flatten").
  Future<void> clearHistory(String filePath) async {
    final logPath = await _logPath(filePath);
    final file = File(logPath);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  Future<String> _logPath(String filePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final logDir = Directory('${dir.path}/revision_history');
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
    final hash = filePath.hashCode.toRadixString(36);
    return '${logDir.path}/$hash.edits.jsonl';
  }
}
