import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the app's UI [Locale] override and persists it on-device.
///
/// `null` means "follow the system locale". Otherwise a specific supported
/// language (en / es / ar ...) is forced. Same singleton + [ValueNotifier]
/// pattern as ThemeController so the UI can react without extra DI.
class LocaleController {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  static const String _key = 'locale_v1';

  /// Watch this to rebuild MaterialApp on language changes. `null` = system.
  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(_key);
      locale.value = (code == null || code.isEmpty) ? null : Locale(code);
    } catch (_) {
      locale.value = null;
    }
  }

  /// Pass `null` to follow the system language.
  Future<void> set(Locale? value) async {
    locale.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, value?.languageCode ?? '');
    } catch (_) {
      // Non-fatal: the in-memory value still applies for this session.
    }
  }
}
