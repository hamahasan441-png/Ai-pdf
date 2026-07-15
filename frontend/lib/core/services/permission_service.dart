import 'package:flutter/material.dart';

/// Permission handling.
///
/// The app deliberately does NOT bundle a dedicated runtime-permission plugin.
/// Each platform plugin already requests exactly what it needs at the moment
/// of use, which keeps the release build lean and avoids native build issues:
///
///  - `image_picker` requests Camera / Photos when the user takes or picks a
///    photo.
///  - `file_picker` uses the Storage Access Framework (no runtime permission).
///  - Saving via the system "Save to…" dialog (SAF) needs no permission.
///  - `flutter_secure_storage` needs no permission.
///  - Mirroring outputs to the app-specific external folder
///    (`getExternalStorageDirectory`) needs no permission on modern Android.
///
/// The methods below are kept as no-ops so callers remain unchanged and the
/// permission flow can be reintroduced later without touching call sites.
class PermissionService {
  PermissionService._();

  /// Called once on startup. No-op: permissions are requested on demand by the
  /// underlying plugins.
  static Future<void> ensureOnStartup(BuildContext context) async {}

  /// Media (photos/storage) access is handled by the picker plugins on demand.
  static Future<bool> ensureMedia() async => true;

  /// Camera access is requested by image_picker when capturing.
  static Future<bool> ensureCamera() async => true;
}
