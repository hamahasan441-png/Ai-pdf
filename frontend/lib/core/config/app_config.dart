class AppConfig {
  AppConfig._();
  static const String appName = 'AI PDF';
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000/api/v1',
  );

  /// OpenRouter endpoint for direct, on-device AI (no backend required).
  static const String openRouterUrl = 'https://openrouter.ai/api/v1/chat/completions';

  /// Optional build-time key, injected by CI via
  /// `--dart-define=OPENROUTER_API_KEY=...` fed from a GitHub Actions secret.
  /// Never hardcode a literal key here (it would leak and be blocked by
  /// GitHub push protection). Empty by default -> user provides the key
  /// in-app, stored encrypted on device only.
  static const String openRouterKeyFromEnv = String.fromEnvironment(
    'OPENROUTER_API_KEY',
    defaultValue: '',
  );

  /// Default free, vision-capable model. Changeable in the app (Profile).
  static const String defaultAiModel = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'google/gemini-2.0-flash-exp:free',
  );

  /// Curated list of good free OpenRouter models: (slug, label, supportsVision).
  /// The free catalog changes over time, so users can also enter a custom slug.
  /// Vision models are needed to "see" documents/images; text-only models are
  /// fine for chatting about already-extracted text.
  static const List<(String, String, bool)> aiModels = [
    ('google/gemini-2.0-flash-exp:free', 'Gemini 2.0 Flash (vision) — recommended', true),
    ('meta-llama/llama-3.2-11b-vision-instruct:free', 'Llama 3.2 Vision', true),
    ('qwen/qwen2.5-vl-72b-instruct:free', 'Qwen2.5-VL 72B (vision)', true),
    ('meta-llama/llama-3.3-70b-instruct:free', 'Llama 3.3 70B (text only)', false),
    ('deepseek/deepseek-chat-v3-0324:free', 'DeepSeek V3 (text only)', false),
  ];
  static const int maxFileSizeMB = 50;
  static const List<String> supportedExtensions = [
    'pdf', 'docx', 'doc', 'png', 'jpg', 'jpeg', 'tiff',
  ];
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 120);
}
