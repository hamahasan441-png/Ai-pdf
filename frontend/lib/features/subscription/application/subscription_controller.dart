import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../data/entitlement_store.dart';
import '../data/purchase_service.dart';
import '../domain/entitlement.dart';

/// Immutable UI state for everything subscription-related.
@immutable
class SubscriptionState {
  final bool initialized;
  final bool storeAvailable;
  final bool loadingProducts;
  final List<ProductDetails> products;
  final Entitlement entitlement;
  final bool purchaseInProgress;
  final String? error;

  const SubscriptionState({
    this.initialized = false,
    this.storeAvailable = false,
    this.loadingProducts = false,
    this.products = const [],
    this.entitlement = const Entitlement.free(),
    this.purchaseInProgress = false,
    this.error,
  });

  bool get isPro => entitlement.isPro;

  ProductDetails? productById(String id) {
    for (final p in products) {
      if (p.id == id) return p;
    }
    return null;
  }

  SubscriptionState copyWith({
    bool? initialized,
    bool? storeAvailable,
    bool? loadingProducts,
    List<ProductDetails>? products,
    Entitlement? entitlement,
    bool? purchaseInProgress,
    String? error,
    bool clearError = false,
  }) {
    return SubscriptionState(
      initialized: initialized ?? this.initialized,
      storeAvailable: storeAvailable ?? this.storeAvailable,
      loadingProducts: loadingProducts ?? this.loadingProducts,
      products: products ?? this.products,
      entitlement: entitlement ?? this.entitlement,
      purchaseInProgress: purchaseInProgress ?? this.purchaseInProgress,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

int _tierRank(ProTier t) {
  switch (t) {
    case ProTier.free:
      return 0;
    case ProTier.monthly:
      return 1;
    case ProTier.yearly:
      return 2;
    case ProTier.lifetime:
      return 3;
  }
}

class SubscriptionController extends StateNotifier<SubscriptionState> {
  SubscriptionController(this._purchases, this._store)
      : super(const SubscriptionState());

  final PurchaseService _purchases;
  final EntitlementStore _store;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Idempotent startup: load cached entitlement, connect to the store, start
  /// listening for purchase updates, and fetch product metadata.
  Future<void> init() async {
    if (state.initialized) return;

    final cached = await _store.load();
    state = state.copyWith(entitlement: cached);

    bool available = false;
    try {
      available = await _purchases.isAvailable();
    } catch (_) {
      available = false;
    }

    // Listen even if products fail to load, so restores/renewals still land.
    _sub = _purchases.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (Object e) {
        state = state.copyWith(error: 'Store connection error.', purchaseInProgress: false);
      },
    );

    state = state.copyWith(initialized: true, storeAvailable: available);

    if (available) {
      await loadProducts();
    }
  }

  Future<void> loadProducts() async {
    state = state.copyWith(loadingProducts: true, clearError: true);
    try {
      final resp = await _purchases.queryProducts();
      if (resp.error != null && kDebugMode) {
        debugPrint('queryProducts error: ${resp.error!.message}');
      }
      state = state.copyWith(products: resp.productDetails, loadingProducts: false);
    } catch (e) {
      state = state.copyWith(
        loadingProducts: false,
        error: 'Could not load plans. Check your connection and Play account.',
      );
    }
  }

  Future<void> buy(ProductDetails product) async {
    state = state.copyWith(purchaseInProgress: true, clearError: true);
    try {
      final started = await _purchases.buy(product);
      if (!started) {
        state = state.copyWith(purchaseInProgress: false, error: 'Could not start the purchase.');
      }
      // Result arrives asynchronously via the purchase stream.
    } catch (e) {
      state = state.copyWith(purchaseInProgress: false, error: 'Purchase failed. Please try again.');
    }
  }

  Future<void> restore() async {
    state = state.copyWith(purchaseInProgress: true, clearError: true);
    try {
      await _purchases.restore();
      // Restored items arrive via the purchase stream; clear the spinner shortly.
      state = state.copyWith(purchaseInProgress: false);
    } catch (e) {
      state = state.copyWith(purchaseInProgress: false, error: 'Restore failed. Please try again.');
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(purchaseInProgress: true, clearError: true);
          break;
        case PurchaseStatus.error:
          state = state.copyWith(
            purchaseInProgress: false,
            error: p.error?.message ?? 'The purchase could not be completed.',
          );
          break;
        case PurchaseStatus.canceled:
          state = state.copyWith(purchaseInProgress: false);
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _grant(p);
          break;
      }

      // Always finish the transaction so Play doesn't auto-refund it.
      try {
        await _purchases.complete(p);
      } catch (_) {}
    }
  }

  Future<void> _grant(PurchaseDetails p) async {
    // NOTE: production must verify p.verificationData server-side before
    // granting. We optimistically grant + cache locally for a good UX and
    // rely on server verification (follow-up) to be authoritative.
    final tier = ProductIds.tierForProduct(p.productID);
    if (tier == ProTier.free) return;

    DateTime? expiry;
    if (tier == ProTier.monthly) {
      expiry = DateTime.now().add(const Duration(days: 31));
    } else if (tier == ProTier.yearly) {
      expiry = DateTime.now().add(const Duration(days: 366));
    }

    final candidate = Entitlement(tier: tier, expiry: expiry);

    // Keep the strongest active entitlement (e.g. lifetime beats monthly).
    final current = state.entitlement;
    final takeCandidate = !current.isPro || _tierRank(tier) >= _tierRank(current.tier);
    final next = takeCandidate ? candidate : current;

    state = state.copyWith(entitlement: next, purchaseInProgress: false, clearError: true);
    await _store.save(next);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

// ---- Providers ----

final purchaseServiceProvider = Provider<PurchaseService>((ref) => PurchaseService());

final entitlementStoreProvider = Provider<EntitlementStore>((ref) => EntitlementStore());

final subscriptionControllerProvider =
    StateNotifierProvider<SubscriptionController, SubscriptionState>((ref) {
  final controller = SubscriptionController(
    ref.read(purchaseServiceProvider),
    ref.read(entitlementStoreProvider),
  );
  // Fire-and-forget startup; UI reacts to state as it initializes.
  controller.init();
  return controller;
});

/// Convenience: is the user currently entitled to Pro features?
final isProProvider = Provider<bool>((ref) {
  return ref.watch(subscriptionControllerProvider).entitlement.isPro;
});
