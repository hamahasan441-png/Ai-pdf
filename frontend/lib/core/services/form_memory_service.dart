import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers answers the user has already given while filling forms — beyond
/// the fixed personal profile — so recurring or custom fields auto-fill next
/// time (e.g. "Emergency contact", "Account number", "Reference").
///
/// Values are stored ON-DEVICE (encrypted, never uploaded) because they can be
/// personal. Works fully offline / in guest mode. Keys are normalized field
/// labels so slightly different wordings still match the same memory slot.
class FormMemoryService {
  FormMemoryService._();
  static final FormMemoryService instance = FormMemoryService._();

  static const _key = 'form_memory_v1';
  static const int _maxEntries = 200; // keep the prompt block bounded

  final _secure = const FlutterSecureStorage();
  final ValueNotifier<Map<String, String>> notifier =
      ValueNotifier<Map<String, String>>({});
  bool _loaded = false;

  Map<String, String> get data => notifier.value;
  bool get hasData => notifier.value.isNotEmpty;

  /// Normalize a field label into a stable memory key.
  static String keyFor(String label) =>
      label.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await _secure.read(key: _key);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          notifier.value =
              decoded.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
        }
      }
    } catch (_) {
      notifier.value = {};
    }
    _loaded = true;
  }

  /// Merge freshly-confirmed answers into memory. Newer values overwrite older
  /// ones for the same field. Empty labels/values are ignored.
  Future<void> remember(Map<String, String> answers) async {
    if (answers.isEmpty) return;
    await load();
    final merged = Map<String, String>.from(notifier.value);
    answers.forEach((label, value) {
      final k = keyFor(label);
      final v = value.trim();
      if (k.isEmpty || v.isEmpty) return;
      merged[k] = v;
    });
    // Bound the store: keep the most recently inserted entries.
    Map<String, String> bounded = merged;
    if (merged.length > _maxEntries) {
      final entries = merged.entries.toList();
      bounded = Map.fromEntries(entries.sublist(entries.length - _maxEntries));
    }
    notifier.value = bounded;
    try {
      await _secure.write(key: _key, value: jsonEncode(bounded));
    } catch (_) {
      // Non-fatal.
    }
  }

  Future<void> clear() async {
    notifier.value = {};
    try {
      await _secure.delete(key: _key);
    } catch (_) {}
  }

  /// A compact block of previously-answered fields the AI can reuse. Returns ''
  /// when nothing has been remembered yet.
  String asPromptBlock() {
    final d = notifier.value;
    if (d.isEmpty) return '';
    final lines = <String>[];
    d.forEach((k, v) {
      if (v.trim().isEmpty) return;
      lines.add('- $k: $v');
    });
    return lines.join('\n');
  }
}
