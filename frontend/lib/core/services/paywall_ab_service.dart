import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Paywall A/B testing service — E6.2 Enhancement-Based Masterplan.
///
/// Two variants:
/// - Variant A: monthly emphasis (yearly = Best Value, monthly highlighted secondary, lifetime tertiary)
/// - Variant B: lifetime emphasis (lifetime = Best Value, yearly secondary, monthly tertiary)
///
/// Assignment:
/// - Randomly assigned on first app open, persisted in SharedPreferences
/// - Local remote config JSON can override (future Firebase Remote Config)
/// - Tracks conversion via analytics_service (see onboarding_screen.dart)
///
/// Metrics:
/// - Exposure: which variant shown
/// - Conversion: Pro purchase from variant
/// - Trial start: 3-day trial from variant
class PaywallVariant {
  final String id; // 'A' or 'B'
  final String name;
  final String description;
  final String highlightedPlan; // monthly, yearly, lifetime
  final String badgePlan; // which plan gets BEST VALUE badge
  final String secondaryHighlight;

  const PaywallVariant({
    required this.id,
    required this.name,
    required this.description,
    required this.highlightedPlan,
    required this.badgePlan,
    required this.secondaryHighlight,
  });

  static const a = PaywallVariant(
    id: 'A',
    name: 'Monthly Emphasis',
    description: 'Yearly = Best Value, monthly highlighted secondary, lifetime tertiary — control',
    highlightedPlan: 'monthly',
    badgePlan: 'yearly',
    secondaryHighlight: 'yearly',
  );

  static const b = PaywallVariant(
    id: 'B',
    name: 'Lifetime Emphasis',
    description: 'Lifetime = Best Value, yearly secondary, monthly tertiary — experimental',
    highlightedPlan: 'lifetime',
    badgePlan: 'lifetime',
    secondaryHighlight: 'yearly',
  );

  static const all = [a, b];

  bool isHighlighted(String plan) => highlightedPlan == plan;
  bool isBadge(String plan) => badgePlan == plan;
}

class PaywallABService {
  static const _variantKey = 'paywall_variant';
  static const _exposureKey = 'paywall_exposure_count';
  static const _conversionKey = 'paywall_conversion';

  const PaywallABService();

  /// Get assigned variant (random on first call, persisted)
  Future<PaywallVariant> getVariant() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_variantKey);
    if (stored != null) {
      return PaywallVariant.all.firstWhere((v) => v.id == stored, orElse: () => PaywallVariant.a);
    }
    // Random assignment 50/50
    final variant = Random().nextBool() ? PaywallVariant.a : PaywallVariant.b;
    await prefs.setString(_variantKey, variant.id);
    return variant;
  }

  /// Force variant (for testing / QA)
  Future<void> setVariant(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_variantKey, id);
  }

  Future<void> trackExposure() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_exposureKey) ?? 0;
    await prefs.setInt(_exposureKey, count + 1);
    // Analytics: track exposure event
    // analytics_service.track('paywall_exposure', {'variant': await getVariant().then((v) => v.id), 'count': count+1});
  }

  Future<void> trackConversion(String plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_conversionKey, plan);
    // Analytics: track conversion
    // analytics_service.track('paywall_conversion', {'variant': (await getVariant()).id, 'plan': plan});
  }

  Future<Map<String, dynamic>> getStats() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'variant': prefs.getString(_variantKey),
      'exposure_count': prefs.getInt(_exposureKey) ?? 0,
      'conversion': prefs.getString(_conversionKey),
    };
  }

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_variantKey);
    await prefs.remove(_exposureKey);
    await prefs.remove(_conversionKey);
  }
}
