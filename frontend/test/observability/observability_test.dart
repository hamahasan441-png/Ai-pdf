import 'package:flutter_test/flutter_test.dart';
import 'package:ai_pdf/core/observability/crash_reporter.dart';
import 'package:ai_pdf/core/observability/analytics_service.dart';

class _FakeReporter implements CrashReporter {
  Object? error;
  StackTrace? stack;
  String? reason;
  bool fatal = false;
  final List<String> logs = [];
  final Map<String, Object> keys = {};

  @override
  Future<void> recordError(Object error, StackTrace? stack,
      {String? reason, bool fatal = false}) async {
    this.error = error;
    this.stack = stack;
    this.reason = reason;
    this.fatal = fatal;
  }

  @override
  Future<void> log(String message) async => logs.add(message);

  @override
  Future<void> setCustomKey(String key, Object value) async => keys[key] = value;
}

class _FakeAnalytics implements AnalyticsService {
  final Map<String, Map<String, Object?>> events = {};
  String? lastScreen;

  @override
  Future<void> logEvent(String name, {Map<String, Object?> params = const {}}) async {
    events[name] = params;
  }

  @override
  Future<void> logScreenView(String screenName) async => lastScreen = screenName;
}

void main() {
  group('Crash facade', () {
    tearDown(() => Crash.setReporter(const ConsoleCrashReporter()));

    test('delegates every call to the injected reporter', () async {
      final fake = _FakeReporter();
      Crash.setReporter(fake);

      final err = StateError('boom');
      final st = StackTrace.current;
      await Crash.recordError(err, st, reason: 'unit', fatal: true);
      await Crash.log('breadcrumb');
      await Crash.setCustomKey('screen', 'home');

      expect(fake.error, same(err));
      expect(fake.stack, same(st));
      expect(fake.reason, 'unit');
      expect(fake.fatal, isTrue);
      expect(fake.logs, contains('breadcrumb'));
      expect(fake.keys['screen'], 'home');
    });
  });

  group('Analytics facade', () {
    tearDown(() => Analytics.setService(const ConsoleAnalytics()));

    test('delegates events and screen views to the injected service', () async {
      final fake = _FakeAnalytics();
      Analytics.setService(fake);

      await Analytics.logEvent(AnalyticsEvents.purchaseSucceeded, params: {'product': 'pro_yearly'});
      await Analytics.logScreenView('paywall');

      expect(fake.events.containsKey(AnalyticsEvents.purchaseSucceeded), isTrue);
      expect(fake.events[AnalyticsEvents.purchaseSucceeded]!['product'], 'pro_yearly');
      expect(fake.lastScreen, 'paywall');
    });
  });
}
