import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entitlement.dart';

/// Persists the last-known [Entitlement] locally so Pro access survives
/// restarts and works offline. This is a CACHE for UX only — it is not a
/// source of truth. Authoritative entitlement must come from server-side
/// purchase verification (see docs/CTO_REVIEW.md).
class EntitlementStore {
  static const String _key = 'entitlement_v1';

  Future<Entitlement> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return const Entitlement.free();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return Entitlement.fromJson(map);
    } catch (_) {
      return const Entitlement.free();
    }
  }

  Future<void> save(Entitlement entitlement) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(entitlement.toJson()));
    } catch (_) {
      // Non-fatal: worst case we re-query the store on next launch.
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {}
  }
}
