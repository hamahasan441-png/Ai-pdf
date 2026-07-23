import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Result of a biometric authentication attempt.
enum BiometricResult { success, failed, cancelled, notAvailable }

/// On-device biometric (fingerprint / face) gating for app-level lock.
///
/// Uses the platform's local authentication APIs via method channel.
/// When biometric hardware is unavailable, falls back to device PIN/pattern.
///
/// ### Usage
/// ```dart
/// final svc = BiometricService();
/// if (await svc.isEnabled) {
///   final result = await svc.authenticate(reason: 'Unlock AI PDF');
///   if (result != BiometricResult.success) return; // block access
/// }
/// ```
class BiometricService {
  static const _channel = MethodChannel('com.aidocassistant.app/biometric');
  static const _prefKey = 'biometric_lock_enabled';

  /// Whether the user has opted into biometric lock (stored in prefs).
  Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefKey) ?? false;
  }

  /// Enable or disable biometric lock.
  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
  }

  /// Whether the device has biometric hardware available.
  Future<bool> get isAvailable async {
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Prompt the user for biometric authentication.
  Future<BiometricResult> authenticate({String reason = 'Authenticate'}) async {
    try {
      final result = await _channel.invokeMethod<String>('authenticate', {
        'reason': reason,
      });
      switch (result) {
        case 'success':
          return BiometricResult.success;
        case 'cancelled':
          return BiometricResult.cancelled;
        case 'not_available':
          return BiometricResult.notAvailable;
        default:
          return BiometricResult.failed;
      }
    } on PlatformException {
      return BiometricResult.failed;
    }
  }
}
