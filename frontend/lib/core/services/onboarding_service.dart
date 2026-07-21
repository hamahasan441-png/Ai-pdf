import 'package:shared_preferences/shared_preferences.dart';

/// Onboarding service — manages the first-open tutorial flow.
///
/// Tracks which onboarding steps the user has completed and whether to show
/// the onboarding screen on app start. Uses SharedPreferences for persistence.
///
/// ### Onboarding steps
/// 1. Welcome — app overview + key value props
/// 2. AI Setup — optional OpenRouter key configuration
/// 3. Profile — set up personal data for auto-fill
/// 4. First document — guide to open/edit/export
class OnboardingService {
  static const String _completedKey = 'onboarding_completed';
  static const String _stepKey = 'onboarding_last_step';
  static const String _versionKey = 'onboarding_version';
  static const int _currentVersion = 1;

  const OnboardingService();

  /// Check if onboarding has been completed.
  Future<bool> isCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    final completed = prefs.getBool(_completedKey) ?? false;
    final version = prefs.getInt(_versionKey) ?? 0;
    // Re-show onboarding if the version has been bumped (new features).
    return completed && version >= _currentVersion;
  }

  /// Mark onboarding as completed.
  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
    await prefs.setInt(_versionKey, _currentVersion);
  }

  /// Get the last completed step (for resume).
  Future<int> lastStep() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_stepKey) ?? 0;
  }

  /// Save progress (step index).
  Future<void> saveStep(int step) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_stepKey, step);
  }

  /// Reset onboarding (for testing or re-triggering).
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_completedKey);
    await prefs.remove(_stepKey);
    await prefs.remove(_versionKey);
  }

  /// Whether to show a specific feature tooltip (one-time hints).
  Future<bool> shouldShowHint(String hintId) async {
    final prefs = await SharedPreferences.getInstance();
    return !(prefs.getBool('hint_$hintId') ?? false);
  }

  /// Mark a hint as shown (won't show again).
  Future<void> markHintShown(String hintId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hint_$hintId', true);
  }
}
