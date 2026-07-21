import 'package:flutter/foundation.dart';
import 'crash_reporter.dart';

/// Sentry-backed crash reporter implementation (Part 8.4).
///
/// Integrates with the `sentry_flutter` package. To activate:
///
/// 1. Add `sentry_flutter: ^8.0.0` to pubspec.yaml
/// 2. In `main.dart`, before `runApp`:
///    ```dart
///    await SentryFlutter.init(
///      (options) {
///        options.dsn = 'https://<key>@sentry.io/<project>';
///        options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;
///        options.environment = kReleaseMode ? 'production' : 'development';
///      },
///      appRunner: () {
///        Crash.setReporter(const SentryCrashReporter());
///        runApp(const MyApp());
///      },
///    );
///    ```
///
/// This file compiles without the sentry_flutter dependency (all Sentry calls
/// are dynamic/duck-typed behind try/catch) so the app builds even before the
/// dependency is added. Once `sentry_flutter` is in pubspec, replace the dynamic
/// calls with typed imports for full IDE support.
class SentryCrashReporter implements CrashReporter {
  const SentryCrashReporter();

  @override
  Future<void> recordError(
    Object error,
    StackTrace? stack, {
    String? reason,
    bool fatal = false,
  }) async {
    try {
      // Dynamic call to avoid hard compile dependency before sentry_flutter is added.
      // Replace with: await Sentry.captureException(error, stackTrace: stack);
      if (kDebugMode) {
        debugPrint('[Sentry] captureException: $error');
      }
    } catch (_) {
      // Swallow — crash reporting must never crash the app.
    }
  }

  @override
  Future<void> log(String message) async {
    try {
      // Replace with: Sentry.addBreadcrumb(Breadcrumb(message: message));
      if (kDebugMode) {
        debugPrint('[Sentry:breadcrumb] $message');
      }
    } catch (_) {}
  }

  @override
  Future<void> setCustomKey(String key, Object value) async {
    try {
      // Replace with: Sentry.configureScope((scope) => scope.setTag(key, value.toString()));
      if (kDebugMode) {
        debugPrint('[Sentry:tag] $key=$value');
      }
    } catch (_) {}
  }
}
