import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles runtime permissions (storage / photos-gallery / camera).
///
/// Android storage permissions changed a lot across versions, so we request a
/// small set that covers every case and let the OS ignore the ones that don't
/// apply:
///   - photos  -> gallery access (Android 13+ READ_MEDIA_IMAGES)
///   - storage -> legacy read/write (Android <= 12)
///   - camera  -> scan / capture documents
class PermissionService {
  PermissionService._();

  static const _askedKey = 'permissions_prompted_v1';

  /// Ask once, on first launch, with a friendly explanation before the OS
  /// dialogs appear. Subsequent launches stay quiet.
  static Future<void> ensureOnStartup(BuildContext context) async {
    if (!Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_askedKey) == true) return;
    if (!context.mounted) return;
    final l = AppLocalizations.of(context)!;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.bPermTitle),
        content: Text(l.bPermBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l.bPermNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l.bPermContinue),
          ),
        ],
      ),
    );

    await prefs.setBool(_askedKey, true);
    if (proceed == true) {
      await requestEssential();
    }
  }

  /// Request the full set. Safe to call multiple times.
  static Future<Map<Permission, PermissionStatus>> requestEssential() async {
    if (!Platform.isAndroid) return {};
    return <Permission>[
      Permission.photos,
      Permission.storage,
      Permission.camera,
    ].request();
  }

  /// Ensure we can access photos/storage before an image or save action.
  /// Returns true if any relevant permission is granted (or not required).
  static Future<bool> ensureMedia() async {
    if (!Platform.isAndroid) return true;
    final statuses = await <Permission>[
      Permission.photos,
      Permission.storage,
    ].request();
    return statuses.values.any((s) => s.isGranted || s.isLimited) ||
        statuses.isEmpty;
  }

  /// Ensure camera access before scanning/capture.
  static Future<bool> ensureCamera() async {
    if (!Platform.isAndroid) return true;
    final status = await Permission.camera.request();
    return status.isGranted || status.isLimited;
  }
}
