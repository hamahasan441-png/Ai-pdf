import 'package:in_app_purchase/in_app_purchase.dart';

import '../domain/entitlement.dart';

/// Thin wrapper over the platform [InAppPurchase] instance. Keeps the plugin
/// surface in one place so the controller depends on a small, mockable API.
class PurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;

  /// Emits purchase updates (buys, restores, pending, errors) from the store.
  Stream<List<PurchaseDetails>> get purchaseStream => _iap.purchaseStream;

  /// Whether the billing service is reachable on this device/account.
  Future<bool> isAvailable() => _iap.isAvailable();

  /// Query product metadata (price, title) for all known product IDs.
  Future<ProductDetailsResponse> queryProducts() =>
      _iap.queryProductDetails(ProductIds.all);

  /// Launch the purchase flow. Both subscriptions and the one-time lifetime
  /// product use [buyNonConsumable] on Android (Play manages renewal).
  Future<bool> buy(ProductDetails product) {
    final param = PurchaseParam(productDetails: product);
    return _iap.buyNonConsumable(purchaseParam: param);
  }

  /// Ask the store to re-deliver previously owned purchases (e.g. new device).
  Future<void> restore() => _iap.restorePurchases();

  /// Acknowledge/finish a purchase so the store stops re-notifying us. Failing
  /// to do this causes Play to auto-refund the purchase after a few days.
  Future<void> complete(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }
}
