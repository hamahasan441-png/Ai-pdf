import 'dart:convert';
import 'dart:ui' show Offset;

import 'package:shared_preferences/shared_preferences.dart';

/// Persists hand-drawn signatures across app restarts so they can be reused
/// instantly and stamped onto forms. Each signature is a polyline: a list of
/// points in the signature pad's own coordinate space.
///
/// Stored locally via SharedPreferences (no cloud, no account needed). Points
/// are plain drawing geometry — not personal identity data — but they still
/// stay on-device.
class SignatureStore {
  SignatureStore._();
  static final SignatureStore instance = SignatureStore._();

  static const _key = 'saved_signatures_v1';
  static const int _maxSignatures = 8;

  /// Load all saved signatures. Returns an empty list if none/failed.
  Future<List<List<Offset>>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <List<Offset>>[];
      for (final sig in decoded) {
        if (sig is! List) continue;
        final pts = <Offset>[];
        for (final p in sig) {
          if (p is Map) {
            final x = (p['x'] as num?)?.toDouble();
            final y = (p['y'] as num?)?.toDouble();
            if (x != null && y != null) pts.add(Offset(x, y));
          }
        }
        if (pts.length > 1) out.add(pts);
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Persist the full set of signatures (bounded to the most recent ones).
  Future<void> save(List<List<Offset>> signatures) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var list = signatures;
      if (list.length > _maxSignatures) {
        list = list.sublist(list.length - _maxSignatures);
      }
      final encoded = jsonEncode([
        for (final sig in list)
          [
            for (final p in sig) {'x': p.dx, 'y': p.dy}
          ]
      ]);
      await prefs.setString(_key, encoded);
    } catch (_) {
      // Non-fatal: persistence is best-effort.
    }
  }
}
