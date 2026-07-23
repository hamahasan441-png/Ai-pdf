import 'package:flutter/services.dart';

/// Local notification service — sends on-device notifications for:
/// - Export/processing complete (when app is backgrounded)
/// - Signing request received
/// - Scheduled reminders (document deadlines from extract-dates)
/// - Download complete (Wi-Fi transfer)
///
/// Uses Android NotificationManager via method channel (no firebase dependency).
/// All notifications are local-only (privacy: no push server).
class NotificationService {
  static const _channel = MethodChannel('com.aidocassistant.app/notifications');

  /// Initialize notification channels (Android 8+).
  Future<void> initialize() async {
    try {
      await _channel.invokeMethod('createChannels', {
        'channels': [
          {'id': 'processing', 'name': 'Processing', 'importance': 'default'},
          {'id': 'signing', 'name': 'Signing', 'importance': 'high'},
          {'id': 'reminders', 'name': 'Reminders', 'importance': 'default'},
          {'id': 'transfer', 'name': 'File Transfer', 'importance': 'low'},
        ],
      });
    } on PlatformException {
      // Older Android or iOS — no-op.
    }
  }

  /// Show a simple notification.
  Future<void> show({
    required String title,
    required String body,
    String channel = 'processing',
    int id = 0,
  }) async {
    try {
      await _channel.invokeMethod('show', {
        'id': id,
        'title': title,
        'body': body,
        'channel': channel,
      });
    } on PlatformException {
      // Notification permission not granted — fail silently.
    }
  }

  /// Show a progress notification (for long-running operations).
  Future<void> showProgress({
    required String title,
    required int progress,
    required int max,
    int id = 1,
  }) async {
    try {
      await _channel.invokeMethod('showProgress', {
        'id': id,
        'title': title,
        'progress': progress,
        'max': max,
        'channel': 'processing',
      });
    } on PlatformException {
      // Fail silently.
    }
  }

  /// Cancel a notification by ID.
  Future<void> cancel(int id) async {
    try {
      await _channel.invokeMethod('cancel', {'id': id});
    } on PlatformException {
      // Ignore.
    }
  }

  /// Schedule a notification for a future time (e.g. document deadline reminder).
  Future<void> schedule({
    required String title,
    required String body,
    required DateTime at,
    int id = 100,
  }) async {
    try {
      await _channel.invokeMethod('schedule', {
        'id': id,
        'title': title,
        'body': body,
        'channel': 'reminders',
        'atMillis': at.millisecondsSinceEpoch,
      });
    } on PlatformException {
      // Fail silently.
    }
  }
}
