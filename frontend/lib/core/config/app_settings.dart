import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Runtime, user-changeable settings.
///
/// - API server URL + AI model: persisted with shared_preferences.
/// - OpenRouter API key: stored ENCRYPTED with flutter_secure_storage, on the
///   device only. It is never written to the repo or bundled into source, so
///   there is no key leak and no GitHub push-protection problem.
///
/// This lets the online AI features work directly on the phone (no backend)
/// using the user's own key. Offline file tools never use any of this.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kApiBaseUrl = 'api_base_url';
  static const _kModel = 'ai_model';
  static const _kOpenRouterKey = 'openrouter_api_key';

  final _secure = const FlutterSecureStorage();

  String _apiBaseUrl = AppConfig.apiBaseUrl;
  String _model = AppConfig.defaultAiModel;

  /// Current API base URL (e.g. https://my-server.com/api/v1).
  String get apiBaseUrl => _apiBaseUrl;

  /// True when a real server has been configured (not the emulator default).
  bool get hasCustomServer => _apiBaseUrl != AppConfig.apiBaseUrl;

  /// AI model slug used for direct OpenRouter calls.
  String get aiModel => _model;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString(_kApiBaseUrl);
      if (v != null && v.trim().isNotEmpty) _apiBaseUrl = v.trim();
      final m = prefs.getString(_kModel);
      if (m != null && m.trim().isNotEmpty) _model = m.trim();
    } catch (_) {
      // Keep compile-time defaults on any failure.
    }
  }

  Future<void> setApiBaseUrl(String url) async {
    final cleaned = url.trim();
    _apiBaseUrl = cleaned.isEmpty ? AppConfig.apiBaseUrl : cleaned;
    await _putString(_kApiBaseUrl, _apiBaseUrl);
  }

  Future<void> setAiModel(String model) async {
    final cleaned = model.trim();
    _model = cleaned.isEmpty ? AppConfig.defaultAiModel : cleaned;
    await _putString(_kModel, _model);
  }

  /// Returns the effective OpenRouter key: the on-device encrypted key if the
  /// user set one, otherwise the optional build-time key. Null if neither.
  Future<String?> openRouterKey() async {
    try {
      final v = await _secure.read(key: _kOpenRouterKey);
      if (v != null && v.trim().isNotEmpty) return v.trim();
    } catch (_) {
      // fall through to env
    }
    return AppConfig.openRouterKeyFromEnv.isEmpty ? null : AppConfig.openRouterKeyFromEnv;
  }

  Future<bool> hasOpenRouterKey() async {
    final k = await openRouterKey();
    return k != null && k.isNotEmpty;
  }

  Future<void> setOpenRouterKey(String key) async {
    final cleaned = key.trim();
    try {
      if (cleaned.isEmpty) {
        await _secure.delete(key: _kOpenRouterKey);
      } else {
        await _secure.write(key: _kOpenRouterKey, value: cleaned);
      }
    } catch (_) {
      // Non-fatal.
    }
  }

  Future<void> _putString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {
      // Non-fatal.
    }
  }
}
