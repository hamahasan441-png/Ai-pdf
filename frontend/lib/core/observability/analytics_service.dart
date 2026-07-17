import 'package:flutter/foundation.dart';

/// Backend-agnostic product analytics.
///
/// Same pattern as [Crash]: the app depends only on this abstraction and the
/// [Analytics] facade. Wire Firebase Analytics / Amplitude / PostHog later via
/// [Analytics.setService] without changing any call site.
abstract class AnalyticsService {
  Future<void> logEvent(String name, {Map<String, Object?> params});
  Future<void> logScreenView(String screenName);
}

/// Default sink: prints in debug, no-ops in release.
class ConsoleAnalytics implements AnalyticsService {
  const ConsoleAnalytics();

  @override
  Future<void> logEvent(String name, {Map<String, Object?> params = const {}}) async {
    if (kDebugMode) debugPrint('[Analytics] $name ${params.isEmpty ? '' : params}');
  }

  @override
  Future<void> logScreenView(String screenName) async {
    if (kDebugMode) debugPrint('[Analytics] screen: $screenName');
  }
}

/// Global facade.
class Analytics {
  Analytics._();

  static AnalyticsService _service = const ConsoleAnalytics();

  static void setService(AnalyticsService service) => _service = service;

  static Future<void> logEvent(String name, {Map<String, Object?> params = const {}}) =>
      _service.logEvent(name, params: params);

  static Future<void> logScreenView(String screenName) =>
      _service.logScreenView(screenName);
}

/// Canonical event names. Keeping these centralized prevents typos and keeps
/// dashboards consistent as the funnel grows.
class AnalyticsEvents {
  AnalyticsEvents._();

  // Monetization funnel
  static const String paywallViewed = 'paywall_viewed';
  static const String purchaseStarted = 'purchase_started';
  static const String purchaseSucceeded = 'purchase_succeeded';
  static const String purchaseRestored = 'purchase_restored';
  static const String purchaseFailed = 'purchase_failed';

  // AI usage
  static const String aiChatSent = 'ai_chat_sent';
  static const String aiFormFilled = 'ai_form_filled';

  // Tools
  static const String toolUsed = 'tool_used';
}
