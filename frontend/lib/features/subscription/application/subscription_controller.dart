import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/config/app_settings.dart';
import '../../../core/observability/analytics_service.dart';
import '../data/billing_verifier.dart';
import '../data/entitlement_store.dart';
import '../data/purchase_service.dart';
import '../domain/entitlement.dart';

/// Immutable UI state for everything subscription-related.
/// Why the last store action failed; the paywall says it in the user's
/// language.
enum SubscriptionError { store, loadPlans, startPurchase, purchaseFailed, restoreFailed, notCompleted, notVerified }

@immutable
class SubscriptionState {
  final bool initialized;
  final bool storeAvailable;
  final bool loadingProducts;
  final List<ProductDetails> products;
  final Entitlement entitlement;
  final bool purchaseInProgress;
  final bool trialUsed;
  final SubscriptionError? error;

  const SubscriptionState({
    this.initialized = false,
    this.storeAvailable = false,
    this.loadingProducts = false,
    this.products = const [],
    this.entitlement = const Entitlement.free(),
    this.purchaseInProgress = false,
    this.trialUsed = false,
    this.error,
  });

  bool get isPro => entitlement.isPro;

  /// True if the one-time free trial can still be started.
  bool get canStartTrial => !entitlement.isPro && !trialUsed;

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
    bool? trialUsed,
    SubscriptionError? error,
    bool clearError = false,
  }) {
    return SubscriptionState(
      initialized: initialized ?? this.initialized,
      storeAvailable: storeAvailable ?? this.storeAvailable,
      loadingProducts: loadingProducts ?? this.loadingProducts,
      products: products ?? this.products,
      entitlement: entitlement ?? this.entitlement,
      purchaseInProgress: purchaseInProgress ?? this.purchaseInProgress,
      trialUsed: trialUsed ?? this.trialUsed,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

int _tierRank(ProTier t) {
  switch (t) {
    case ProTier.free:
      return 0;
    case ProTier.trial:
      return 1;
    case ProTier.monthly:
      return 2;
    case ProTier.yearly:
      return 3;
    case ProTier.lifetime:
      return 4;
  }
}

class SubscriptionController extends StateNotifier<SubscriptionState> {
  SubscriptionController(this._purchases, this._store)
      : super(const SubscriptionState());

  final PurchaseService _purchases;
  final EntitlementStore _store;
  final BillingVerifier _verifier = BillingVerifier();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Idempotent startup: load cached entitlement, connect to the store, start
  /// listening for purchase updates, and fetch product metadata.
  Future<void> init() async {
    if (state.initialized) return;

    final cached = await _store.load();
    final trialUsed = await _store.isTrialUsed();
    state = state.copyWith(entitlement: cached, trialUsed: trialUsed);

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
        state = state.copyWith(error: SubscriptionError.store, purchaseInProgress: false);
      },
    );

    state = state.copyWith(initialized: true, storeAvailable: available);

    if (available) {
      await loadProducts();
      await _refreshOwned();
    }
  }

  /// Asks the store, quietly, for what this account owns. Android does not
  /// push subscription renewals into the purchase stream, so without this a
  /// paying subscriber lost Pro once the local 31/366-day expiry passed. An
  /// active subscription comes back through the stream and is granted
  /// again; a cancelled one does not, and lapses at its expiry.
  Future<void> _refreshOwned() async {
    try {
      await _purchases.restore();
    } catch (_) {
      // Offline or the store is busy: the cached entitlement stands until
      // the next launch tries again. Nothing for the user to act on.
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
        error: SubscriptionError.loadPlans,
      );
    }
  }

  /// Start the one-time 3-day free trial (unlocks all Pro features). No-op if
  /// already Pro or the trial was used before.
  Future<void> startFreeTrial() async {
    if (!state.canStartTrial) return;
    final entitlement = Entitlement(
      tier: ProTier.trial,
      expiry: DateTime.now().add(const Duration(days: 3)),
    );
    await _store.save(entitlement);
    await _store.markTrialUsed();
    Analytics.logEvent(AnalyticsEvents.trialStarted);
    state = state.copyWith(entitlement: entitlement, trialUsed: true, clearError: true);
  }

  Future<void> buy(ProductDetails product) async {
    state = state.copyWith(purchaseInProgress: true, clearError: true);
    Analytics.logEvent(AnalyticsEvents.purchaseStarted, params: {'product': product.id});
    try {
      final started = await _purchases.buy(product);
      if (!started) {
        state = state.copyWith(purchaseInProgress: false, error: SubscriptionError.startPurchase);
      }
      // Result arrives asynchronously via the purchase stream.
    } catch (e) {
      state = state.copyWith(purchaseInProgress: false, error: SubscriptionError.purchaseFailed);
    }
  }

  Future<void> restore() async {
    state = state.copyWith(purchaseInProgress: true, clearError: true);
    try {
      await _purchases.restore();
      // Restored items arrive via the purchase stream; clear the spinner shortly.
      state = state.copyWith(purchaseInProgress: false);
    } catch (e) {
      state = state.copyWith(purchaseInProgress: false, error: SubscriptionError.restoreFailed);
    }
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(purchaseInProgress: true, clearError: true);
          break;
        case PurchaseStatus.error:
          Analytics.logEvent(AnalyticsEvents.purchaseFailed,
              params: {'product': p.productID, 'error': p.error?.message});
          state = state.copyWith(
            purchaseInProgress: false,
            error: SubscriptionError.notCompleted,
          );
          break;
        case PurchaseStatus.canceled:
          state = state.copyWith(purchaseInProgress: false);
          break;
        case PurchaseStatus.purchased:
          await _grant(p);
          Analytics.logEvent(AnalyticsEvents.purchaseSucceeded, params: {'product': p.productID});
          break;
        case PurchaseStatus.restored:
          await _grant(p);
          Analytics.logEvent(AnalyticsEvents.purchaseRestored, params: {'product': p.productID});
          break;
      }

      // Always finish the transaction so Play doesn't auto-refund it.
      try {
        await _purchases.complete(p);
      } catch (_) {}
    }
  }

  Future<void> _grant(PurchaseDetails p) async {
    var tier = ProductIds.tierForProduct(p.productID);
    if (tier == ProTier.free) return;

    DateTime? expiry;
    if (tier == ProTier.monthly) {
      expiry = DateTime.now().add(const Duration(days: 31));
    } else if (tier == ProTier.yearly) {
      expiry = DateTime.now().add(const Duration(days: 366));
    }

    // Prefer authoritative server verification when a backend is configured.
    // If it can't run (no server / offline), fall back to the optimistic grant.
    final server = await _verifier.verify(
      productId: p.productID,
      purchaseToken: p.verificationData.serverVerificationData,
      isSubscription: ProductIds.subscriptions.contains(p.productID),
    );
    if (server != null) {
      if (!server.valid) {
        state = state.copyWith(
          purchaseInProgress: false,
          error: SubscriptionError.notVerified,
        );
        return;
      }
      if (server.tier != ProTier.free) tier = server.tier;
      expiry = server.expiry ?? expiry;
    }

    final candidate = Entitlement(tier: tier, expiry: expiry);

    // Keep the strongest active entitlement (e.g. lifetime beats monthly).
    final current = state.entitlement;
    final takeCandidate = !current.isPro || _tierRank(tier) >= _tierRank(current.tier);
    final next = takeCandidate ? candidate : current;

    state = state.copyWith(entitlement: next, purchaseInProgress: false, clearError: true);
    await _store.save(next);
    // Remember the purchase token so managed AI can prove Pro server-side.
    if (next.isPro) {
      await AppSettings.instance.setProToken(p.verificationData.serverVerificationData);
    }
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
