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

  /// Sentinel for "let the app pick the best model per task".
  static const String autoModel = 'auto';

  /// Default free, vision-capable model. Also used as the safety fallback if a
  /// chosen model fails — MUST be a real slug (never 'auto').
  static const String defaultAiModel = String.fromEnvironment(
    'AI_MODEL',
    defaultValue: 'google/gemma-4-27b-it:free',
  );

  /// Best free models the auto-router picks between.
  static const String autoVisionModel = 'google/gemma-4-27b-it:free';
  static const String autoTextModel = 'deepseek/deepseek-chat-v3-0324:free';

  /// Curated models available through OpenRouter. One API key, all providers.
  /// The free catalog changes over time; users can also enter a custom slug.
  /// Vision models can "see" documents/images directly.
  ///
  /// Format: (slug, label, supportsVision)

  /// Combined list for the model picker UI.
  static const List<(String, String, bool)> aiModels = [
    // --- AUTO ---
    ('auto', 'Auto — best model for each task', true),
    // --- FREE (no credits needed) ---
    ('google/gemma-4-27b-it:free', 'Gemma 4 27B (vision) — recommended', true),
    ('google/gemma-4-31b-it:free', 'Gemma 4 31B (vision, 256K ctx)', true),
    ('google/gemma-4-26b-a4b-it:free', 'Gemma 4 26B MoE (vision, fast)', true),
    ('google/gemini-2.5-flash-preview:free', 'Gemini 2.5 Flash (vision)', true),
    ('nvidia/llama-3.1-nemotron-70b-instruct:free', 'Nemotron 70B (text)', false),
    ('deepseek/deepseek-chat-v3-0324:free', 'DeepSeek V3 (text)', false),
    // --- PREMIUM (pay-per-token via OpenRouter) ---
    ('openai/gpt-4o', 'GPT-4o (vision) — OpenAI', true),
    ('openai/gpt-4o-mini', 'GPT-4o Mini (vision, cheap) — OpenAI', true),
    ('anthropic/claude-sonnet-4', 'Claude Sonnet 4 (vision) — Anthropic', true),
    ('anthropic/claude-3.5-haiku', 'Claude 3.5 Haiku (vision, fast)', true),
    ('google/gemini-2.5-pro-preview', 'Gemini 2.5 Pro (vision) — Google', true),
    ('meta-llama/llama-4-maverick', 'Llama 4 Maverick (vision) — Meta', true),
  ];
  static const int maxFileSizeMB = 50;
  static const List<String> supportedExtensions = [
    'pdf', 'docx', 'doc', 'png', 'jpg', 'jpeg', 'tiff',
  ];
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 120);
}
