/// AdMob unit IDs.
///
/// Defaults to Google's official TEST unit IDs so the app is safe to run in
/// development without a real AdMob account. For release, pass your real IDs
/// via --dart-define and set ADS_TEST=false, e.g.:
///   flutter build apk --dart-define=ADS_TEST=false \
///     --dart-define=ADMOB_BANNER_ID=ca-app-pub-xxx/yyy \
///     --dart-define=ADMOB_INTERSTITIAL_ID=ca-app-pub-xxx/zzz \
///     --dart-define=ADMOB_REWARDED_ID=ca-app-pub-xxx/www
class AdConfig {
  AdConfig._();

  static const bool testAds =
      bool.fromEnvironment('ADS_TEST', defaultValue: true);

  // Official Google test unit IDs (Android).
  static const String _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const String _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const String _testRewarded = 'ca-app-pub-3940256099942544/5224354917';

  static const String _prodBanner =
      String.fromEnvironment('ADMOB_BANNER_ID', defaultValue: '');
  static const String _prodInterstitial =
      String.fromEnvironment('ADMOB_INTERSTITIAL_ID', defaultValue: '');
  static const String _prodRewarded =
      String.fromEnvironment('ADMOB_REWARDED_ID', defaultValue: '');

  static String get bannerUnitId =>
      (testAds || _prodBanner.isEmpty) ? _testBanner : _prodBanner;
  static String get interstitialUnitId =>
      (testAds || _prodInterstitial.isEmpty) ? _testInterstitial : _prodInterstitial;
  static String get rewardedUnitId =>
      (testAds || _prodRewarded.isEmpty) ? _testRewarded : _prodRewarded;
}
