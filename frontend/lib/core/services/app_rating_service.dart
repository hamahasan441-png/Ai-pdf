import 'package:shared_preferences/shared_preferences.dart';

/// Smart app rating prompt service.
///
/// Shows the "Rate this app" prompt at the RIGHT time — not on first open,
/// not during a critical flow, but after a positive interaction:
/// - After 3rd successful export
/// - After 5th app open
/// - At least 3 days after install
/// - Never if already rated or dismissed 3 times
///
/// This maximizes positive ratings while minimizing annoyance.
class AppRatingService {
  static const String _openCountKey = 'rating_open_count';
  static const String _exportCountKey = 'rating_export_count';
  static const String _firstOpenKey = 'rating_first_open';
  static const String _ratedKey = 'rating_rated';
  static const String _dismissCountKey = 'rating_dismiss_count';

  static const int _minOpens = 5;
  static const int _minExports = 3;
  static const int _minDaysSinceInstall = 3;
  static const int _maxDismissals = 3;

  const AppRatingService();

  /// Call on every app open.
  Future<void> recordOpen() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_openCountKey) ?? 0) + 1;
    await prefs.setInt(_openCountKey, count);
    if (!prefs.containsKey(_firstOpenKey)) {
      await prefs.setString(_firstOpenKey, DateTime.now().toIso8601String());
    }
  }

  /// Call after every successful export.
  Future<void> recordExport() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_exportCountKey) ?? 0) + 1;
    await prefs.setInt(_exportCountKey, count);
  }

  /// Check if conditions are met to show the rating prompt.
  Future<bool> shouldShowPrompt() async {
    final prefs = await SharedPreferences.getInstance();

    // Already rated? Never show again.
    if (prefs.getBool(_ratedKey) ?? false) return false;

    // Dismissed too many times? Give up.
    final dismissals = prefs.getInt(_dismissCountKey) ?? 0;
    if (dismissals >= _maxDismissals) return false;

    // Minimum opens.
    final opens = prefs.getInt(_openCountKey) ?? 0;
    if (opens < _minOpens) return false;

    // Minimum exports.
    final exports = prefs.getInt(_exportCountKey) ?? 0;
    if (exports < _minExports) return false;

    // Minimum days since install.
    final firstOpen = prefs.getString(_firstOpenKey);
    if (firstOpen != null) {
      final installDate = DateTime.tryParse(firstOpen);
      if (installDate != null) {
        final days = DateTime.now().difference(installDate).inDays;
        if (days < _minDaysSinceInstall) return false;
      }
    }

    return true;
  }

  /// Mark as rated (never prompt again).
  Future<void> markRated() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ratedKey, true);
  }

  /// Record a dismissal.
  Future<void> recordDismissal() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_dismissCountKey) ?? 0) + 1;
    await prefs.setInt(_dismissCountKey, count);
  }
}
