import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the app's [ThemeMode] (system / light / dark) and persists the user's
/// choice on-device. Follows the same singleton + [ValueNotifier] pattern used
/// elsewhere (e.g. RecentFilesService), so the UI can react without extra DI.
class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  static const String _key = 'theme_mode_v1';

  /// Watch this to rebuild on theme changes.
  final ValueNotifier<ThemeMode> mode = ValueNotifier<ThemeMode>(ThemeMode.system);

  /// Load the persisted choice. Call once at startup before runApp().
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      mode.value = _parse(prefs.getString(_key));
    } catch (_) {
      mode.value = ThemeMode.system;
    }
  }

  Future<void> set(ThemeMode value) async {
    mode.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value.name);
    } catch (_) {
      // Non-fatal: the in-memory value still applies for this session.
    }
  }

  static ThemeMode _parse(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}
