import 'package:flutter/foundation.dart';

/// Backend-agnostic crash / error reporting.
///
/// The app depends only on this abstraction and the [Crash] facade — never on a
/// specific vendor. A concrete backend (Firebase Crashlytics, Sentry, or a
/// custom endpoint) can be injected at startup via [Crash.setReporter] WITHOUT
/// touching any call sites. Until then a console sink is used so errors are
/// surfaced in debug instead of being silently swallowed.
abstract class CrashReporter {
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  });

  /// Breadcrumb-style log attached to the next crash report.
  Future<void> log(String message);

  /// Attach a searchable key/value to subsequent reports (e.g. screen, tier).
  Future<void> setCustomKey(String key, Object value);
}

/// Default sink: prints in debug, no-ops in release. Never throws.
class ConsoleCrashReporter implements CrashReporter {
  const ConsoleCrashReporter();

  @override
  Future<void> recordError(Object error, StackTrace? stack,
      {String? reason, bool fatal = false}) async {
    if (kDebugMode) {
      debugPrint('[Crash${fatal ? ':FATAL' : ''}]'
          '${reason != null ? ' ($reason)' : ''} $error');
      if (stack != null) debugPrintStack(stackTrace: stack);
    }
  }

  @override
  Future<void> log(String message) async {
    if (kDebugMode) debugPrint('[Crash:log] $message');
  }

  @override
  Future<void> setCustomKey(String key, Object value) async {
    if (kDebugMode) debugPrint('[Crash:key] $key=$value');
  }
}

/// Global facade. Call sites use `Crash.recordError(...)`; the backend is
/// swapped once at startup.
class Crash {
  Crash._();

  static CrashReporter _reporter = const ConsoleCrashReporter();

  /// Inject a real backend at startup (e.g. a CrashlyticsCrashReporter).
  static void setReporter(CrashReporter reporter) => _reporter = reporter;

  static CrashReporter get reporter => _reporter;

  static Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) =>
      _reporter.recordError(error, stack, reason: reason, fatal: fatal);

  static Future<void> log(String message) => _reporter.log(message);

  static Future<void> setCustomKey(String key, Object value) =>
      _reporter.setCustomKey(key, value);
}
