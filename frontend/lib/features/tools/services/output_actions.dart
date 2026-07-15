import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/permission_service.dart';

/// Unified output actions for any generated file.
///
/// Big-app standard: after producing a file the user can always
///   - Save it to their device (choose location via the system dialog)
///   - Share it to any app
///   - Preview it in-app
///
/// Every generated file is also mirrored to a browsable "AI PDF" folder on
/// device storage so nothing is ever lost.
///
/// Every method is wrapped so a failure shows a message instead of crashing.
class OutputActions {
  OutputActions._();

  /// Save a file to a user-chosen location using the system Save dialog.
  /// Requests storage/gallery permission first (only prompts when needed).
  static Future<void> save(BuildContext context, String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _snack(context, 'File no longer exists');
        return;
      }

      // Ask for storage/gallery access when the user actually saves.
      await PermissionService.ensureMedia();

      final bytes = await file.readAsBytes();
      final name = path.split('/').last;

      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save to device',
        fileName: name,
        bytes: bytes,
      );

      // Also keep a copy in the browsable AI PDF folder.
      final mirrored = await mirrorToPublicFolder(path);

      if (context.mounted) {
        if (saved != null) {
          _snack(context, 'Saved to device');
        } else if (mirrored != null) {
          _snack(context, 'Saved to "AI PDF" folder');
        } else {
          _snack(context, 'Save cancelled');
        }
      }
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not save: $e');
    }
  }

  /// Best-effort copy of [path] into a browsable "AI PDF" folder on external
  /// storage. Returns the destination path, or null if unavailable.
  ///
  /// Uses the app-specific external directory, which is readable by file
  /// managers and requires no special permission on modern Android.
  static Future<String?> mirrorToPublicFolder(String path) async {
    try {
      final base = await getExternalStorageDirectory();
      if (base == null) return null;
      final dir = Directory('${base.path}/AI PDF');
      if (!await dir.exists()) await dir.create(recursive: true);
      final src = File(path);
      if (!await src.exists()) return null;
      final destPath = '${dir.path}/${path.split('/').last}';
      if (File(destPath).existsSync() && destPath != path) {
        return destPath;
      }
      if (destPath == path) return path;
      await src.copy(destPath);
      return destPath;
    } catch (_) {
      return null;
    }
  }

  /// Share a file to any app.
  static Future<void> share(BuildContext context, String path,
      {String? text}) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _snack(context, 'File no longer exists');
        return;
      }
      await Share.shareXFiles([XFile(path)], text: text);
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not share: $e');
    }
  }

  /// Share multiple files at once.
  static Future<void> shareMany(BuildContext context, List<String> paths,
      {String? text}) async {
    try {
      final existing = paths.where((p) => File(p).existsSync()).toList();
      if (existing.isEmpty) {
        _snack(context, 'No files to share');
        return;
      }
      await Share.shareXFiles(existing.map((p) => XFile(p)).toList(), text: text);
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not share: $e');
    }
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}
