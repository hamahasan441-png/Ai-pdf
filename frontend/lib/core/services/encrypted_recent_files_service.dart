import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encrypted recent files service — E5.1 Enhancement-Based Masterplan.
///
/// Migrates from `recent_files_v1` JSON blob in SharedPreferences (unencrypted)
/// to encrypted storage via FlutterSecureStorage (Android Keystore backed) +
/// provides pagination for 1000s items (future drift/Isar migration path).
///
/// ### Migration
/// 1. Read old key `recent_files_v1` if exists
/// 2. Write to secure storage key `recent_files_encrypted_v1` as JSON (secure storage encrypts at OS level)
/// 3. Delete old key
/// 4. Future reads use secure storage only
///
/// ### Pagination
/// - `listPaginated(page: 0, pageSize: 20)` returns slice sorted newest first
/// - Benchmark target: <16ms for 1k items (in-memory slice is O(pageSize), not O(n) decode each time — we cache decoded list)
///
/// ### Drift path (future)
/// For 1000s items, move to `drift` package with SQL pagination. This service's API already supports
/// page/pageSize so drift migration is drop-in: replace internal list with SQL query LIMIT/OFFSET.
///
/// ### Security
/// - Secure storage uses Android Keystore / iOS Keychain, encrypted at rest
/// - No file paths logged
/// - File existence check still filters stale entries
class RecentFile {
  final String path;
  final String name;
  final String action;
  final bool isPdf;
  final int at; // epoch millis

  RecentFile({
    required this.path,
    required this.name,
    required this.action,
    required this.isPdf,
    required this.at,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'action': action,
        'isPdf': isPdf,
        'at': at,
      };

  factory RecentFile.fromJson(Map<String, dynamic> j) => RecentFile(
        path: j['path'] as String,
        name: j['name'] as String? ?? (j['path'] as String).split('/').last,
        action: j['action'] as String? ?? 'Saved',
        isPdf: j['isPdf'] as bool? ?? (j['path'] as String).toLowerCase().endsWith('.pdf'),
        at: j['at'] as int? ?? 0,
      );

  DateTime get date => DateTime.fromMillisecondsSinceEpoch(at);
}

class EncryptedRecentFilesService {
  EncryptedRecentFilesService._();
  static final EncryptedRecentFilesService instance = EncryptedRecentFilesService._();

  static const _oldKey = 'recent_files_v1';
  static const _secureKey = 'recent_files_encrypted_v1';
  static const _max = 1000; // increased from 60 to 1000 for drift-ready
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final ValueNotifier<List<RecentFile>> notifier = ValueNotifier(<RecentFile>[]);
  bool _loaded = false;
  // Cached decoded list for pagination performance
  List<RecentFile> _cached = [];

  List<RecentFile> get items => notifier.value;

  Future<void> load() async {
    try {
      // Try secure storage first
      String? raw = await _storage.read(key: _secureKey);
      if (raw == null || raw.isEmpty) {
        // Migration: read old unencrypted
        final prefs = await SharedPreferences.getInstance();
        raw = prefs.getString(_oldKey);
        if (raw != null && raw.isNotEmpty) {
          // Migrate to secure
          await _storage.write(key: _secureKey, value: raw);
          await prefs.remove(_oldKey);
          // ignore: avoid_print
          debugPrint('[EncryptedRecentFiles] Migrated ${raw.length} chars from SharedPreferences to SecureStorage');
        }
      }
      if (raw != null && raw.isNotEmpty) {
        final decoded = (jsonDecode(raw) as List)
            .map((e) => RecentFile.fromJson(e as Map<String, dynamic>))
            .where((f) {
              try {
                return File(f.path).existsSync();
              } catch (_) {
                return false;
              }
            })
            .toList();
        // Sort newest first
        decoded.sort((a, b) => b.at.compareTo(a.at));
        _cached = decoded;
        notifier.value = decoded;
      }
    } catch (_) {
      notifier.value = <RecentFile>[];
      _cached = [];
    }
    _loaded = true;
  }

  /// Paginated list — page 0 = newest 20, etc. <16ms for 1k items target.
  Future<List<RecentFile>> listPaginated({int page = 0, int pageSize = 20}) async {
    if (!_loaded) await load();
    final start = page * pageSize;
    if (start >= _cached.length) return [];
    final end = (start + pageSize).clamp(0, _cached.length);
    return _cached.sublist(start, end);
  }

  Future<int> count() async {
    if (!_loaded) await load();
    return _cached.length;
  }

  Future<void> add(String path, {String action = 'Saved'}) async {
    if (!_loaded) await load();
    final name = path.split('/').last;
    final isPdf = name.toLowerCase().endsWith('.pdf');
    final list = List<RecentFile>.from(_cached)..removeWhere((f) => f.path == path);
    list.insert(
      0,
      RecentFile(
        path: path,
        name: name,
        action: action,
        isPdf: isPdf,
        at: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    if (list.length > _max) list.removeRange(_max, list.length);
    _cached = list;
    notifier.value = list;
    await _persist();
  }

  Future<void> remove(String path) async {
    _cached = List<RecentFile>.from(_cached)..removeWhere((f) => f.path == path);
    notifier.value = _cached;
    await _persist();
  }

  Future<void> clear() async {
    _cached = [];
    notifier.value = [];
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final jsonStr = jsonEncode(_cached.map((f) => f.toJson()).toList());
      await _storage.write(key: _secureKey, value: jsonStr);
    } catch (_) {
      // Best-effort
    }
  }

  /// Benchmark helper — measures listPaginated time for 1k items
  Future<Duration> benchmark() async {
    if (!_loaded) await load();
    final sw = Stopwatch()..start();
    for (var i = 0; i < 10; i++) {
      await listPaginated(page: i % (_cached.length ~/ 20 + 1), pageSize: 20);
    }
    sw.stop();
    return sw.elapsed;
  }
}
