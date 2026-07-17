import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../observability/crash_reporter.dart';
import 'ad_config.dart';

/// Central, tasteful ads controller.
///
/// Design goals (least-annoying monetization that still drives Pro upgrades):
///  - Banners only on browse screens (not the editor / AI chat / processing).
///  - Interstitials only at a natural break (after a tool finishes), with a
///    frequency cap and a warm-up so first impressions stay clean.
///  - NO ads at all for Pro users.
///  - GDPR/UMP consent requested before serving.
class AdsService {
  AdsService._();
  static final AdsService instance = AdsService._();

  bool _initialized = false;
  bool _pro = false;

  InterstitialAd? _interstitial;
  DateTime _lastInterstitial = DateTime.fromMillisecondsSinceEpoch(0);
  int _completedOps = 0;

  static const Duration _minGap = Duration(minutes: 3);
  static const int _warmupOps = 2; // no interstitial for the first N actions

  /// Whether ads should be served right now (free tier + initialized).
  bool get showAds => _initialized && !_pro;

  /// Initialize the SDK + request consent. Safe to call once at startup.
  Future<void> init() async {
    if (_initialized) return;
    try {
      await _requestConsent();
      await MobileAds.instance.initialize();
      _initialized = true;
      if (!_pro) _loadInterstitial();
    } catch (e, s) {
      Crash.recordError(e, s, reason: 'ads init');
    }
  }

  /// Called from the app root whenever Pro status changes.
  void setPro(bool pro) {
    if (_pro == pro) return;
    _pro = pro;
    if (pro) {
      _interstitial?.dispose();
      _interstitial = null;
    } else if (_initialized) {
      _loadInterstitial();
    }
  }

  Future<void> _requestConsent() async {
    try {
      final done = Completer<void>();
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(),
        () async {
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((_) {});
          } catch (_) {}
          if (!done.isCompleted) done.complete();
        },
        (_) {
          if (!done.isCompleted) done.complete();
        },
      );
      await done.future.timeout(const Duration(seconds: 6), onTimeout: () {});
    } catch (_) {
      // Consent is best-effort; never block startup.
    }
  }

  void _loadInterstitial() {
    if (_pro || _interstitial != null) return;
    InterstitialAd.load(
      adUnitId: AdConfig.interstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  /// Call at a natural break (after a tool finishes). Frequency-capped, warmed
  /// up, and never shown to Pro. Non-blocking; degrades silently.
  Future<void> maybeShowInterstitial() async {
    if (_pro || !_initialized) return;
    _completedOps++;
    if (_completedOps <= _warmupOps) return;
    if (DateTime.now().difference(_lastInterstitial) < _minGap) return;

    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    _interstitial = null;
    _lastInterstitial = DateTime.now();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) {
        a.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (a, _) {
        a.dispose();
        _loadInterstitial();
      },
    );
    try {
      await ad.show();
    } catch (_) {
      ad.dispose();
      _loadInterstitial();
    }
  }

  /// Opt-in rewarded ad (e.g. "watch to unlock a perk"). Returns true if the
  /// user earned the reward. Never shown to Pro.
  Future<bool> showRewarded() async {
    if (_pro || !_initialized) return false;
    final result = Completer<bool>();
    try {
      RewardedAd.load(
        adUnitId: AdConfig.rewardedUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            var earned = false;
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (a) {
                a.dispose();
                if (!result.isCompleted) result.complete(earned);
              },
              onAdFailedToShowFullScreenContent: (a, _) {
                a.dispose();
                if (!result.isCompleted) result.complete(false);
              },
            );
            ad.show(onUserEarnedReward: (_, __) => earned = true);
          },
          onAdFailedToLoad: (_) {
            if (!result.isCompleted) result.complete(false);
          },
        ),
      );
    } catch (_) {
      if (!result.isCompleted) result.complete(false);
    }
    return result.future.timeout(const Duration(seconds: 45), onTimeout: () => false);
  }
}
