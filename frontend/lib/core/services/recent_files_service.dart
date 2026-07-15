import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A single entry in the "Recent Files" list.
class RecentFile {
  final String path;
  final String name;
  final String action; // e.g. 'Compressed', 'Edited', 'Merged'
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

/// Tracks every file the app creates / edits / saves so the user can find
/// them again. Persisted with shared_preferences (small JSON manifest).
///
/// Stale entries (whose underlying file was deleted) are filtered out on load,
/// so the list always reflects what actually exists on device.
class RecentFilesService {
  RecentFilesService._();
  static final RecentFilesService instance = RecentFilesService._();

  static const _key = 'recent_files_v1';
  static const _max = 60;

  /// UI listens to this to stay in sync.
  final ValueNotifier<List<RecentFile>> notifier = ValueNotifier(<RecentFile>[]);
  bool _loaded = false;

  List<RecentFile> get items => notifier.value;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = (jsonDecode(raw) as List)
            .map((e) => RecentFile.fromJson(e as Map<String, dynamic>))
            .where((f) => File(f.path).existsSync())
            .toList();
        notifier.value = decoded;
      }
    } catch (_) {
      // Corrupt manifest -> start clean.
      notifier.value = <RecentFile>[];
    }
    _loaded = true;
  }

  /// Record (or bump to top) a file. Deduplicates by path.
  Future<void> add(String path, {String action = 'Saved'}) async {
    if (!_loaded) await load();
    final name = path.split('/').last;
    final isPdf = name.toLowerCase().endsWith('.pdf');
    final list = List<RecentFile>.from(notifier.value)
      ..removeWhere((f) => f.path == path);
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
    notifier.value = list;
    await _persist();
  }

  Future<void> remove(String path) async {
    final list = List<RecentFile>.from(notifier.value)
      ..removeWhere((f) => f.path == path);
    notifier.value = list;
    await _persist();
  }

  Future<void> clear() async {
    notifier.value = <RecentFile>[];
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(notifier.value.map((f) => f.toJson()).toList()),
      );
    } catch (_) {
      // Non-fatal: persistence best-effort.
    }
  }
}
