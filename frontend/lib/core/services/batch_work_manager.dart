import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart' as wm;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Batch WorkManager + Notifications — E4.5 Enhancement-Based Masterplan.
///
/// For large jobs (>50MB or >200 pages), schedule background work with foreground notification
/// (progress callback, cancel). Small jobs use isolate via compute() in image_ops.dart
///
/// ### Design
/// - Small jobs (<50MB, <200 pages): use compute() isolate path (existing image_ops.dart)
/// - Large jobs: register WorkManager one-off task with inputData {filePaths, operation}
/// - Foreground notification shows progress via flutter_local_notifications
/// - Cancel via Workmanager.cancelByUniqueName
/// - Progress callback via MethodChannel? For V1, we poll via shared preferences or just show indeterminate

class BatchWorkManager {
  static const _taskName = 'batch_process_large';
  static const _uniqueName = 'ai_pdf_batch_large';

  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  const BatchWorkManager();

  Future<void> initialize() async {
    try {
      await _notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        ),
      );
      await wm.Workmanager().initialize(_callbackDispatcher, isInDebugMode: kDebugMode);
    } catch (e) {
      debugPrint('[BatchWorkManager] init failed: $e');
    }
  }

  Future<void> scheduleLargeJob({
    required List<String> filePaths,
    required String operation,
  }) async {
    try {
      await wm.Workmanager().registerOneOffTask(
        _uniqueName,
        _taskName,
        inputData: {
          'filePaths': filePaths,
          'operation': operation,
          'fileCount': filePaths.length,
        },
        existingWorkPolicy: wm.ExistingWorkPolicy.replace,
        constraints: wm.Constraints(
          networkType: wm.NetworkType.notRequired,
          requiresBatteryNotLow: false,
        ),
      );
      await _showNotification('Batch processing started', '${filePaths.length} files queued for $operation');
    } catch (e) {
      debugPrint('[BatchWorkManager] schedule failed: $e');
    }
  }

  Future<void> cancel() async {
    try {
      await wm.Workmanager().cancelByUniqueName(_uniqueName);
      await _notifications.cancel(1001);
    } catch (_) {}
  }

  Future<void> _showNotification(String title, String body, {int progress = -1}) async {
    try {
      final android = AndroidNotificationDetails(
        'batch_channel',
        'Batch Processing',
        channelDescription: 'Shows progress for large PDF batch operations',
        importance: Importance.low,
        priority: Priority.low,
        showProgress: progress >= 0,
        maxProgress: 100,
        progress: progress,
        ongoing: true,
      );
      await _notifications.show(
        1001,
        title,
        body,
        NotificationDetails(android: android),
      );
    } catch (_) {}
  }

  Future<void> showProgress(int processed, int total, String operation) async {
    final pct = ((processed / total) * 100).toInt().clamp(0, 100);
    await _showNotification(
      'Batch $operation',
      '$processed / $total files processed',
      progress: pct,
    );
    if (processed >= total) {
      await _notifications.cancel(1001);
      final doneAndroid = const AndroidNotificationDetails(
        'batch_channel',
        'Batch Processing',
        channelDescription: 'Batch done',
        importance: Importance.high,
      );
      await _notifications.show(
        1002,
        'Batch complete',
        '$total files processed via $operation',
        NotificationDetails(android: doneAndroid),
      );
    }
  }

  /// Heuristic: large job if total size >50MB or any file >200 pages (we approximate via file size)
  Future<bool> isLargeJob(List<String> filePaths) async {
    int totalSize = 0;
    for (final p in filePaths) {
      try {
        final f = File(p);
        if (await f.exists()) {
          totalSize += await f.length();
        }
      } catch (_) {}
    }
    return totalSize > 50 * 1024 * 1024 || filePaths.length > 10;
  }
}

// WorkManager callback dispatcher — runs in background isolate
@pragma('vm:entry-point')
void _callbackDispatcher() {
  wm.Workmanager().executeTask((task, inputData) async {
    try {
      final filePaths = (inputData?['filePaths'] as List?)?.cast<String>() ?? [];
      final operation = inputData?['operation'] as String? ?? 'compress';
      // Simulate batch processing — in production, call OfflinePdfService / image_ops via compute()
      for (var i = 0; i < filePaths.length; i++) {
        // Do work...
        await Future.delayed(const Duration(milliseconds: 500));
        // Update progress notification would require local_notifications in background isolate
        // For V1, just log
        debugPrint('[BatchWorkManager BG] $operation ${i + 1}/${filePaths.length}');
      }
      return Future.value(true);
    } catch (e) {
      debugPrint('[BatchWorkManager BG] failed: $e');
      return Future.value(false);
    }
  });
}
