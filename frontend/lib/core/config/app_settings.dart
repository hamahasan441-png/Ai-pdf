import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Runtime, user-changeable settings — now multi-provider.
///
/// The user picks an AI provider (OpenRouter, OpenAI, Anthropic, Perplexity,
/// or a custom/local server) and supplies their OWN key for it. Keys are
/// stored ENCRYPTED per-provider with flutter_secure_storage, on the device
/// only — never in the repo or source. The selected model and (for custom) the
/// endpoint are stored per-provider in shared_preferences.
///
/// Offline file tools never use any of this.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _kApiBaseUrl = 'api_base_url';
  static const _kProvider = 'ai_provider';
  static const _kCustomEndpoint = 'ai_custom_endpoint';
  // Per-provider keys/models use these prefixes.
  static const _kKeyPrefix = 'aikey_'; // secure storage
  static const _kModelPrefix = 'aimodel_'; // prefs

  final _secure = const FlutterSecureStorage();

  String _apiBaseUrl = AppConfig.apiBaseUrl;
  String _provider = AppConfig.providerOpenRouter;
  String _customEndpoint = '';
  final Map<String, String> _models = {}; // providerId -> model slug

  // ---- Optional backend base URL (legacy/account flows) ----
  String get apiBaseUrl => _apiBaseUrl;
  bool get hasCustomServer => _apiBaseUrl != AppConfig.apiBaseUrl;

  // ---- Provider ----
  String get providerId => _provider;
  AiProviderDef get provider => AppConfig.providerById(_provider);

  /// The chat/completions (or Anthropic messages) endpoint for the current
  /// provider. For "custom", it's the user-provided URL. For "managed", it's
  /// the app's backend proxy at <server>/ai/chat.
  String get aiEndpoint {
    if (provider.managed) {
      final base = _apiBaseUrl.endsWith('/')
          ? _apiBaseUrl.substring(0, _apiBaseUrl.length - 1)
          : _apiBaseUrl;
      return '$base/ai/chat';
    }
    return provider.id == AppConfig.providerCustom ? _customEndpoint : provider.endpoint;
  }

  String get customEndpoint => _customEndpoint;

  /// True if the current provider uses the Anthropic Messages API.
  bool get isAnthropic => provider.anthropic;

  /// True if the current provider is the app's managed backend proxy.
  bool get isManaged => provider.managed;

  /// True if the current provider requires an API key.
  bool get needsKey => provider.needsKey;

  /// Selected model slug for the current provider (falls back to its default).
  String get aiModel {
    final m = _models[_provider];
    if (m != null && m.trim().isNotEmpty) return m.trim();
    return provider.defaultModel;
  }

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base = prefs.getString(_kApiBaseUrl);
      if (base != null && base.trim().isNotEmpty) _apiBaseUrl = base.trim();

      final p = prefs.getString(_kProvider);
      if (p != null && AppConfig.providers.any((d) => d.id == p)) _provider = p;

      final ce = prefs.getString(_kCustomEndpoint);
      if (ce != null) _customEndpoint = ce.trim();

      for (final d in AppConfig.providers) {
        final m = prefs.getString('$_kModelPrefix${d.id}');
        if (m != null && m.trim().isNotEmpty) _models[d.id] = m.trim();
      }

      // Migrate any legacy single-key/model settings to OpenRouter.
      final legacyModel = prefs.getString('ai_model');
      if (legacyModel != null && legacyModel.trim().isNotEmpty) {
        _models.putIfAbsent(AppConfig.providerOpenRouter, () => legacyModel.trim());
      }
      final legacyKey = await _secure.read(key: 'openrouter_api_key');
      if (legacyKey != null && legacyKey.trim().isNotEmpty) {
        final existing = await _secure.read(key: '$_kKeyPrefix${AppConfig.providerOpenRouter}');
        if (existing == null || existing.isEmpty) {
          await _secure.write(
              key: '$_kKeyPrefix${AppConfig.providerOpenRouter}', value: legacyKey.trim());
        }
      }
    } catch (_) {
      // Keep compile-time defaults on any failure.
    }
  }

  Future<void> setProvider(String id) async {
    if (AppConfig.providers.any((d) => d.id == id)) {
      _provider = id;
      await _putString(_kProvider, id);
    }
  }

  Future<void> setCustomEndpoint(String url) async {
    _customEndpoint = url.trim();
    await _putString(_kCustomEndpoint, _customEndpoint);
  }

  Future<void> setAiModel(String model) async {
    final cleaned = model.trim();
    if (cleaned.isEmpty) {
      _models.remove(_provider);
    } else {
      _models[_provider] = cleaned;
    }
    await _putString('$_kModelPrefix$_provider', cleaned);
  }

  Future<void> setApiBaseUrl(String url) async {
    final cleaned = url.trim();
    _apiBaseUrl = cleaned.isEmpty ? AppConfig.apiBaseUrl : cleaned;
    await _putString(_kApiBaseUrl, _apiBaseUrl);
  }

  // ---- API key (per provider, encrypted) ----

  /// Effective key for the current provider: on-device encrypted key, else the
  /// optional build-time OpenRouter key (only for the OpenRouter provider).
  Future<String?> apiKey() async {
    try {
      final v = await _secure.read(key: '$_kKeyPrefix$_provider');
      if (v != null && v.trim().isNotEmpty) return v.trim();
    } catch (_) {
      // fall through
    }
    if (_provider == AppConfig.providerOpenRouter &&
        AppConfig.openRouterKeyFromEnv.isNotEmpty) {
      return AppConfig.openRouterKeyFromEnv;
    }
    return null;
  }

  Future<bool> hasApiKey() async {
    if (!needsKey) return true;
    final k = await apiKey();
    return k != null && k.isNotEmpty;
  }

  Future<void> setApiKey(String key) async {
    final cleaned = key.trim();
    try {
      if (cleaned.isEmpty) {
        await _secure.delete(key: '$_kKeyPrefix$_provider');
      } else {
        await _secure.write(key: '$_kKeyPrefix$_provider', value: cleaned);
      }
    } catch (_) {
      // Non-fatal.
    }
  }

  // ---- Backward-compatible aliases (used by existing call sites) ----
  Future<String?> openRouterKey() => apiKey();
  Future<bool> hasOpenRouterKey() => hasApiKey();
  Future<void> setOpenRouterKey(String key) => setApiKey(key);

  Future<void> _putString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {
      // Non-fatal.
    }
  }
}
