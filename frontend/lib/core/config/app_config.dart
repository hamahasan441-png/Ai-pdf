/// Describes one AI provider the app can talk to directly from the phone.
///
/// Most providers (OpenRouter, OpenAI, Perplexity, custom/local) speak the
/// OpenAI "chat/completions" format with a Bearer token. Anthropic uses its
/// own "messages" API (x-api-key header, different request/response shape), so
/// it is flagged with [anthropic] and handled specially in the service.
class AiProviderDef {
  final String id;
  final String label;
  final String endpoint; // '' = user-provided (custom/local)
  final bool anthropic;

  /// Managed provider: the app's own backend proxy (`/ai/chat`). No key needed;
  /// the server holds the key and meters free usage.
  final bool managed;
  final bool needsKey;
  final String keysUrl; // where to get an API key
  final String defaultModel;
  final List<(String, String, bool)> models; // (slug, label, supportsVision)

  const AiProviderDef({
    required this.id,
    required this.label,
    required this.endpoint,
    required this.defaultModel,
    required this.models,
    this.anthropic = false,
    this.managed = false,
    this.needsKey = true,
    this.keysUrl = '',
  });
}

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
    ('google/gemini-2.5-pro', 'Gemini 2.5 Pro (vision, top-tier) — Google', true),
    ('google/gemini-2.5-flash', 'Gemini 2.5 Flash (vision, fast + cheap) — Google', true),
    ('openai/gpt-4o', 'GPT-4o (vision) — OpenAI', true),
    ('openai/gpt-4o-mini', 'GPT-4o Mini (vision, cheap) — OpenAI', true),
    ('anthropic/claude-sonnet-4', 'Claude Sonnet 4 (vision) — Anthropic', true),
    ('anthropic/claude-3.5-haiku', 'Claude 3.5 Haiku (vision, fast)', true),
    ('google/gemini-2.5-pro-preview', 'Gemini 2.5 Pro Preview (vision) — Google', true),
    ('meta-llama/llama-4-maverick', 'Llama 4 Maverick (vision) — Meta', true),
  ];
  // ---- Multi-provider support ------------------------------------------
  // Users can pick a provider and use their OWN key for it. OpenRouter is the
  // easiest (one key → every model). OpenAI/Anthropic/Perplexity talk to those
  // companies directly. "Custom" targets any OpenAI-compatible server incl. a
  // local/LAN one for offline use.

  static const String providerManaged = 'managed';
  static const String providerOpenRouter = 'openrouter';
  static const String providerOpenAI = 'openai';
  static const String providerAnthropic = 'anthropic';
  static const String providerPerplexity = 'perplexity';
  static const String providerCustom = 'custom';

  static const List<AiProviderDef> providers = [
    AiProviderDef(
      id: providerManaged,
      label: 'AI PDF (managed — no key needed)',
      endpoint: '', // computed at runtime: <server>/ai/chat
      managed: true,
      needsKey: false,
      defaultModel: '',
      models: [],
    ),
    AiProviderDef(
      id: providerOpenRouter,
      label: 'OpenRouter — all models, one key (recommended)',
      endpoint: openRouterUrl,
      keysUrl: 'openrouter.ai/keys',
      defaultModel: autoModel,
      models: aiModels,
    ),
    AiProviderDef(
      id: providerOpenAI,
      label: 'OpenAI (ChatGPT)',
      endpoint: 'https://api.openai.com/v1/chat/completions',
      keysUrl: 'platform.openai.com/api-keys',
      defaultModel: 'gpt-4o-mini',
      models: [
        ('gpt-4o', 'GPT-4o (vision)', true),
        ('gpt-4o-mini', 'GPT-4o mini (vision, cheap)', true),
        ('gpt-4.1', 'GPT-4.1 (vision)', true),
        ('gpt-4.1-mini', 'GPT-4.1 mini (vision)', true),
      ],
    ),
    AiProviderDef(
      id: providerAnthropic,
      label: 'Anthropic (Claude)',
      endpoint: 'https://api.anthropic.com/v1/messages',
      anthropic: true,
      keysUrl: 'console.anthropic.com/settings/keys',
      defaultModel: 'claude-3-5-haiku-latest',
      models: [
        ('claude-sonnet-4-20250514', 'Claude Sonnet 4 (vision)', true),
        ('claude-3-7-sonnet-latest', 'Claude 3.7 Sonnet (vision)', true),
        ('claude-3-5-sonnet-latest', 'Claude 3.5 Sonnet (vision)', true),
        ('claude-3-5-haiku-latest', 'Claude 3.5 Haiku (vision, cheap)', true),
      ],
    ),
    AiProviderDef(
      id: providerPerplexity,
      label: 'Perplexity',
      endpoint: 'https://api.perplexity.ai/chat/completions',
      keysUrl: 'perplexity.ai/settings/api',
      defaultModel: 'sonar',
      models: [
        ('sonar', 'Sonar (fast, web-aware)', false),
        ('sonar-pro', 'Sonar Pro (web-aware)', false),
        ('sonar-reasoning', 'Sonar Reasoning', false),
      ],
    ),
    AiProviderDef(
      id: providerCustom,
      label: 'Custom / local server (offline)',
      endpoint: '', // user provides
      needsKey: false,
      defaultModel: '',
      models: [],
    ),
  ];

  static AiProviderDef providerById(String id) =>
      providers.firstWhere((p) => p.id == id, orElse: () => providers.first);

  static const int maxFileSizeMB = 50;
  static const List<String> supportedExtensions = [
    'pdf', 'docx', 'doc', 'png', 'jpg', 'jpeg', 'tiff',
  ];
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(seconds: 120);
}
