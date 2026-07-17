import 'package:flutter_test/flutter_test.dart';
import 'package:ai_pdf/features/subscription/domain/entitlement.dart';

void main() {
  group('Entitlement.isPro', () {
    test('free is not pro', () {
      const e = Entitlement.free();
      expect(e.isPro, isFalse);
      expect(e.tier, ProTier.free);
      expect(e.isLifetime, isFalse);
    });

    test('lifetime is always pro', () {
      const e = Entitlement(tier: ProTier.lifetime);
      expect(e.isPro, isTrue);
      expect(e.isLifetime, isTrue);
    });

    test('subscription with a future expiry is pro', () {
      final e = Entitlement(
        tier: ProTier.monthly,
        expiry: DateTime.now().add(const Duration(days: 5)),
      );
      expect(e.isPro, isTrue);
    });

    test('subscription with a past expiry is NOT pro', () {
      final e = Entitlement(
        tier: ProTier.yearly,
        expiry: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(e.isPro, isFalse);
    });

    test('subscription with unknown (null) expiry does not lock out a payer', () {
      const e = Entitlement(tier: ProTier.monthly);
      expect(e.isPro, isTrue);
    });
  });

  group('Entitlement JSON round-trip', () {
    test('serializes and restores a subscription with expiry', () {
      final expiry = DateTime.utc(2030, 1, 2, 3, 4, 5);
      final e = Entitlement(tier: ProTier.yearly, expiry: expiry);
      final restored = Entitlement.fromJson(e.toJson());
      expect(restored.tier, ProTier.yearly);
      expect(restored.expiry, expiry);
    });

    test('lifetime has no expiry after round-trip', () {
      const e = Entitlement(tier: ProTier.lifetime);
      final restored = Entitlement.fromJson(e.toJson());
      expect(restored.tier, ProTier.lifetime);
      expect(restored.expiry, isNull);
    });

    test('unknown tier decodes to free', () {
      final restored = Entitlement.fromJson({'tier': 'platinum', 'expiry': null});
      expect(restored.tier, ProTier.free);
      expect(restored.isPro, isFalse);
    });

    test('malformed expiry decodes to null (not a crash)', () {
      final restored = Entitlement.fromJson({'tier': 'monthly', 'expiry': 'not-a-date'});
      expect(restored.tier, ProTier.monthly);
      expect(restored.expiry, isNull);
    });
  });

  group('ProductIds', () {
    test('maps product IDs to the correct tier', () {
      expect(ProductIds.tierForProduct(ProductIds.monthly), ProTier.monthly);
      expect(ProductIds.tierForProduct(ProductIds.yearly), ProTier.yearly);
      expect(ProductIds.tierForProduct(ProductIds.lifetime), ProTier.lifetime);
      expect(ProductIds.tierForProduct('unknown_sku'), ProTier.free);
    });

    test('all contains every known product', () {
      expect(ProductIds.all, containsAll(<String>{
        ProductIds.monthly,
        ProductIds.yearly,
        ProductIds.lifetime,
      }));
      expect(ProductIds.subscriptions, {ProductIds.monthly, ProductIds.yearly});
      expect(ProductIds.nonConsumables, {ProductIds.lifetime});
    });
  });

  group('ProTierX', () {
    test('isPro is true for every paid tier', () {
      expect(ProTier.free.isPro, isFalse);
      expect(ProTier.monthly.isPro, isTrue);
      expect(ProTier.yearly.isPro, isTrue);
      expect(ProTier.lifetime.isPro, isTrue);
    });

    test('labels are human readable', () {
      expect(ProTier.free.label, 'Free');
      expect(ProTier.lifetime.label, contains('Lifetime'));
    });
  });
}
