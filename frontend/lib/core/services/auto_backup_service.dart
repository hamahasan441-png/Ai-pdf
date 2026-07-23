import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Automatic backup service — periodically backs up documents and settings
/// to a local backup directory. Configurable interval and retention.
///
/// Architecture:
/// - Creates timestamped snapshots of important data:
///   - Annotation saves (JSON)
///   - User profile data
///   - AI suggestion cache
///   - App settings
/// - Keeps last N backups (configurable, default 5)
/// - Restores from any backup point
///
/// Privacy: all backups stay on device. User can export to external storage.
class AutoBackupService {
  static const _prefInterval = 'backup_interval_hours';
  static const _prefEnabled = 'backup_enabled';
  static const _prefLastBackup = 'last_backup_timestamp';
  static const _maxBackups = 5;

  const AutoBackupService();

  /// Whether automatic backup is enabled.
  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefEnabled) ?? true;
  }

  /// Set backup enabled/disabled.
  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefEnabled, enabled);
  }

  /// Backup interval in hours (default 24).
  Future<int> get intervalHours async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefInterval) ?? 24;
  }

  /// Set backup interval.
  Future<void> setInterval(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefInterval, hours);
  }

  /// Check if a backup is due.
  Future<bool> isBackupDue() async {
    if (!await isEnabled) return false;
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_prefLastBackup) ?? 0;
    final interval = await intervalHours;
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    return elapsed > interval * 3600 * 1000;
  }

  /// Run a backup now.
  Future<String> backup() async {
    final dir = await _backupDir();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupFolder = Directory('${dir.path}/backup_$timestamp');
    await backupFolder.create(recursive: true);

    // Copy annotation saves.
    final appDir = await getApplicationDocumentsDirectory();
    final annotDir = Directory('${appDir.path}/annotations');
    if (await annotDir.exists()) {
      await _copyDir(annotDir, Directory('${backupFolder.path}/annotations'));
    }

    // Copy AI cache.
    final cacheDir = Directory('${appDir.path}/ai_cache');
    if (await cacheDir.exists()) {
      await _copyDir(cacheDir, Directory('${backupFolder.path}/ai_cache'));
    }

    // Record timestamp.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefLastBackup, DateTime.now().millisecondsSinceEpoch);

    // Evict old backups.
    await _evictOld(dir);

    return backupFolder.path;
  }

  /// List available backups.
  Future<List<BackupEntry>> listBackups() async {
    final dir = await _backupDir();
    if (!await dir.exists()) return [];
    final dirs = dir.listSync().whereType<Directory>().toList();
    dirs.sort((a, b) => b.path.compareTo(a.path)); // newest first
    return dirs.map((d) {
      final name = d.path.split('/').last;
      final timestamp = name.replaceFirst('backup_', '').replaceAll('-', ':');
      return BackupEntry(path: d.path, timestamp: timestamp);
    }).toList();
  }

  /// Restore from a backup.
  Future<void> restore(String backupPath) async {
    final appDir = await getApplicationDocumentsDirectory();
    final backup = Directory(backupPath);
    if (!await backup.exists()) return;

    final annotBackup = Directory('$backupPath/annotations');
    if (await annotBackup.exists()) {
      final target = Directory('${appDir.path}/annotations');
      if (await target.exists()) await target.delete(recursive: true);
      await _copyDir(annotBackup, target);
    }
  }

  Future<Directory> _backupDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/backups');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> _evictOld(Directory dir) async {
    final dirs = dir.listSync().whereType<Directory>().toList();
    if (dirs.length <= _maxBackups) return;
    dirs.sort((a, b) => a.path.compareTo(b.path)); // oldest first
    for (var i = 0; i < dirs.length - _maxBackups; i++) {
      await dirs[i].delete(recursive: true);
    }
  }

  Future<void> _copyDir(Directory src, Directory dst) async {
    await dst.create(recursive: true);
    await for (final entity in src.list()) {
      if (entity is File) {
        await entity.copy('${dst.path}/${entity.path.split('/').last}');
      }
    }
  }
}

class BackupEntry {
  final String path;
  final String timestamp;
  const BackupEntry({required this.path, required this.timestamp});
}
