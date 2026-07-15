import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Runtime, user-changeable settings (persisted with shared_preferences).
///
/// The AI server URL can be changed inside the app (Profile screen) so the
/// online AI features can be pointed at a hosted backend WITHOUT rebuilding
/// the APK. Offline file tools never use this.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kApiBaseUrl = 'api_base_url';

  String _apiBaseUrl = AppConfig.apiBaseUrl;

  /// Current API base URL (e.g. https://my-server.com/api/v1).
  String get apiBaseUrl => _apiBaseUrl;

  /// True when a real server has been configured (not the emulator default).
  bool get hasCustomServer => _apiBaseUrl != AppConfig.apiBaseUrl;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kApiBaseUrl);
      if (v != null && v.trim().isNotEmpty) {
        _apiBaseUrl = v.trim();
      }
    } catch (_) {
      // Keep compile-time default on any failure.
    }
  }

  Future<void> setApiBaseUrl(String url) async {
    final cleaned = url.trim();
    _apiBaseUrl = cleaned.isEmpty ? AppConfig.apiBaseUrl : cleaned;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kApiBaseUrl, _apiBaseUrl);
    } catch (_) {
      // Non-fatal.
    }
  }
}
