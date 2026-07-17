/// Domain model for the app's Pro entitlement and the Play Billing products
/// that grant it. Pure Dart — no Flutter or plugin imports — so it stays easy
/// to unit-test.

/// The Play Console product IDs. These must match exactly the products you
/// create in the Play Console (Monetize > Products).
class ProductIds {
  ProductIds._();

  /// Auto-renewing subscription (monthly base plan).
  static const String monthly = 'pro_monthly';

  /// Auto-renewing subscription (yearly base plan).
  static const String yearly = 'pro_yearly';

  /// One-time, non-consumable purchase — unlocks Pro forever.
  static const String lifetime = 'pro_lifetime';

  /// Subscription IDs (queried/handled together).
  static const Set<String> subscriptions = {monthly, yearly};

  /// One-time (non-consumable) product IDs.
  static const Set<String> nonConsumables = {lifetime};

  /// Everything we query from the store.
  static const Set<String> all = {monthly, yearly, lifetime};

  static ProTier tierForProduct(String productId) {
    switch (productId) {
      case monthly:
        return ProTier.monthly;
      case yearly:
        return ProTier.yearly;
      case lifetime:
        return ProTier.lifetime;
      default:
        return ProTier.free;
    }
  }
}

enum ProTier { free, trial, monthly, yearly, lifetime }

extension ProTierX on ProTier {
  bool get isPro => this != ProTier.free;
  bool get isTrial => this == ProTier.trial;

  String get label {
    switch (this) {
      case ProTier.free:
        return 'Free';
      case ProTier.trial:
        return 'Free Trial';
      case ProTier.monthly:
        return 'Pro (Monthly)';
      case ProTier.yearly:
        return 'Pro (Yearly)';
      case ProTier.lifetime:
        return 'Pro (Lifetime)';
    }
  }
}

/// Immutable snapshot of what the user is entitled to.
class Entitlement {
  final ProTier tier;

  /// For subscriptions, the local best-effort expiry used for OFFLINE gating.
  /// Null for [ProTier.free] and [ProTier.lifetime].
  ///
  /// SECURITY NOTE: this local expiry is convenience only and is trivially
  /// spoofable on a rooted device. Production MUST verify purchases
  /// server-side (Play Developer API / RTDN) before granting paid features.
  /// See docs/CTO_REVIEW.md (managed backend) for the follow-up.
  final DateTime? expiry;

  const Entitlement({required this.tier, this.expiry});

  const Entitlement.free()
      : tier = ProTier.free,
        expiry = null;

  bool get isLifetime => tier == ProTier.lifetime;

  /// True if the user should currently have Pro access (offline view).
  bool get isPro {
    if (tier == ProTier.free) return false;
    if (tier == ProTier.lifetime) return true;
    final e = expiry;
    if (e == null) return true; // unknown expiry -> don't lock out a payer
    return DateTime.now().isBefore(e);
  }

  Entitlement copyWith({ProTier? tier, DateTime? expiry, bool clearExpiry = false}) {
    return Entitlement(
      tier: tier ?? this.tier,
      expiry: clearExpiry ? null : (expiry ?? this.expiry),
    );
  }

  Map<String, dynamic> toJson() => {
        'tier': tier.name,
        'expiry': expiry?.toIso8601String(),
      };

  factory Entitlement.fromJson(Map<String, dynamic> json) {
    final tierName = json['tier'] as String?;
    final tier = ProTier.values.firstWhere(
      (t) => t.name == tierName,
      orElse: () => ProTier.free,
    );
    final expiryStr = json['expiry'] as String?;
    return Entitlement(
      tier: tier,
      expiry: expiryStr == null ? null : DateTime.tryParse(expiryStr),
    );
  }
}
