import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Frame-budget telemetry + Performance dashboard — E4.6 / E4.3 Phase 6.
///
/// Uses WidgetsBinding.addTimingsCallback to log slow frames (<55fps) with
/// current page count + annotation count + lowRamMode flag. Sends to crash_reporter / Sentry
/// facade via analytics_service.dart, and optionally to backend POST /admin/perf/ingest for aggregated
/// p95 per route dashboard.
///
/// This is additive: no existing code modified, just a service that can be started in main.dart
/// after app initialization.
class FrameTelemetryService {
  static final FrameTelemetryService _instance = FrameTelemetryService._internal();
  factory FrameTelemetryService() => _instance;
  FrameTelemetryService._internal();

  bool _started = false;
  final List<FrameTiming> _recentTimings = [];
  static const int _maxRecent = 120; // 2 seconds at 60fps

  int _slowFrames = 0;
  int _totalFrames = 0;

  Timer? _reportTimer;

  // Configurable threshold: 16ms for 60fps, we consider <55fps slow ( >18ms )
  static const Duration _slowThreshold = Duration(milliseconds: 18);

  // Callbacks for external reporting
  void Function(Map<String, dynamic> event)? onSlowFrame;
  void Function(Map<String, dynamic> summary)? onSummary;

  // Context for logging
  int _currentPageCount = 0;
  int _annotationCount = 0;
  bool _lowRamMode = false;
  String _currentRoute = '/home';

  void setContext({int? pageCount, int? annotationCount, bool? lowRamMode, String? route}) {
    if (pageCount != null) _currentPageCount = pageCount;
    if (annotationCount != null) _annotationCount = annotationCount;
    if (lowRamMode != null) _lowRamMode = lowRamMode;
    if (route != null) _currentRoute = route;
  }

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    // Periodic summary every 30s
    _reportTimer = Timer.periodic(const Duration(seconds: 30), (_) => _reportSummary());
    debugPrint('[FrameTelemetry] started');
  }

  void stop() {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    _reportTimer?.cancel();
    _reportTimer = null;
    debugPrint('[FrameTelemetry] stopped');
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _totalFrames++;
      _recentTimings.add(t);
      if (_recentTimings.length > _maxRecent) {
        _recentTimings.removeAt(0);
      }

      // Check if frame was slow: totalSpan > threshold
      final span = t.totalSpan;
      if (span > _slowThreshold) {
        _slowFrames++;
        final event = {
          'timestamp': DateTime.now().toIso8601String(),
          'totalSpanMs': span.inMilliseconds,
          'buildDurationMs': t.buildDuration.inMilliseconds,
          'rasterDurationMs': t.rasterDuration.inMilliseconds,
          'pageCount': _currentPageCount,
          'annotationCount': _annotationCount,
          'lowRamMode': _lowRamMode,
          'route': _currentRoute,
          'slow': true,
        };
        // Send to crash reporter / analytics
        onSlowFrame?.call(event);
        debugPrint('[FrameTelemetry] slow frame: ${span.inMilliseconds}ms route=$_currentRoute pages=$_currentPageCount ann=$_annotationCount lowRam=$_lowRamMode');
      }
    }
  }

  void _reportSummary() {
    if (_totalFrames == 0) return;
    final slowRate = _slowFrames / _totalFrames;
    // Compute p95 from recent timings
    final sorted = List<FrameTiming>.from(_recentTimings)..sort((a, b) => a.totalSpan.compareTo(b.totalSpan));
    Duration p50 = const Duration(milliseconds: 8);
    Duration p95 = const Duration(milliseconds: 16);
    Duration p99 = const Duration(milliseconds: 20);
    if (sorted.isNotEmpty) {
      p50 = sorted[(sorted.length * 0.5).floor().clamp(0, sorted.length - 1)].totalSpan;
      p95 = sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)].totalSpan;
      p99 = sorted[(sorted.length * 0.99).floor().clamp(0, sorted.length - 1)].totalSpan;
    }

    final summary = {
      'timestamp': DateTime.now().toIso8601String(),
      'totalFrames': _totalFrames,
      'slowFrames': _slowFrames,
      'slowRate': slowRate,
      'p50Ms': p50.inMilliseconds,
      'p95Ms': p95.inMilliseconds,
      'p99Ms': p99.inMilliseconds,
      'pageCount': _currentPageCount,
      'annotationCount': _annotationCount,
      'lowRamMode': _lowRamMode,
      'route': _currentRoute,
    };
    onSummary?.call(summary);
    // Reset counters for next period
    _slowFrames = 0;
    _totalFrames = 0;
  }

  Map<String, dynamic> getStats() {
    return {
      'started': _started,
      'totalFrames': _totalFrames,
      'slowFrames': _slowFrames,
      'recentCount': _recentTimings.length,
      'pageCount': _currentPageCount,
      'annotationCount': _annotationCount,
      'lowRamMode': _lowRamMode,
      'route': _currentRoute,
    };
  }
}
