import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/permission_service.dart';
import '../../../core/utils/error_text.dart';

/// Unified output actions for any generated file.
///
/// Big-app standard: after producing a file the user can always
///   - Save it to their device (choose location via the system dialog)
///   - Share it to any app
///   - Preview it in-app
///
/// Every generated file is also mirrored to a browsable "Pdoczy" folder on
/// device storage so nothing is ever lost.
///
/// Every method is wrapped so a failure shows a message instead of crashing.
class OutputActions {
  OutputActions._();

  /// Save a file to a user-chosen location using the system Save dialog.
  /// Requests storage/gallery permission first (only prompts when needed).
  static Future<void> save(BuildContext context, String path) async {
    final l10n = AppLocalizations.of(context);
    try {
      final file = File(path);
      if (!await file.exists()) {
        if (context.mounted) _snack(context, l10n?.fileMissing ?? 'The file no longer exists');
        return;
      }

      // Ask for storage/gallery access when the user actually saves.
      await PermissionService.ensureMedia();

      final bytes = await file.readAsBytes();
      final name = path.split('/').last;

      final saved = await FilePicker.platform.saveFile(
        dialogTitle: l10n?.saveToDevice ?? 'Save to device',
        fileName: name,
        bytes: bytes,
      );

      // Also keep a copy in the browsable Pdoczy folder.
      await mirrorToPublicFolder(path);

      if (context.mounted) {
        // Cancelling the dialog is a cancel, whatever the background copy
        // did: that folder is not one the user can browse on Android 11+.
        _snack(context, saved != null ? (l10n?.savedToDevice ?? 'Saved to device') : (l10n?.saveCancelled ?? 'Save cancelled'));
      }
    } catch (e) {
      if (context.mounted) _snack(context, l10n?.saveFailed(describeError(e, l10n)) ?? 'Could not save');
    }
  }

  /// Best-effort copy of [path] into a browsable "Pdoczy" folder on external
  /// storage. Returns the destination path, or null if unavailable.
  ///
  /// Uses the app-specific external directory, which is readable by file
  /// managers and requires no special permission on modern Android.
  static Future<String?> mirrorToPublicFolder(String path) async {
    try {
      final base = await getExternalStorageDirectory();
      if (base == null) return null;
      final dir = Directory('${base.path}/Pdoczy');
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
    final l10n = AppLocalizations.of(context);
    try {
      final file = File(path);
      if (!await file.exists()) {
        if (context.mounted) _snack(context, l10n?.fileMissing ?? 'The file no longer exists');
        return;
      }
      await Share.shareXFiles([XFile(path)], text: text);
    } catch (e) {
      if (context.mounted) _snack(context, l10n?.couldNotShare(describeError(e, l10n)) ?? 'Could not share');
    }
  }

  /// Share multiple files at once.
  static Future<void> shareMany(BuildContext context, List<String> paths,
      {String? text}) async {
    final l10n = AppLocalizations.of(context);
    try {
      final existing = paths.where((p) => File(p).existsSync()).toList();
      if (existing.isEmpty) {
        _snack(context, l10n?.noFilesToShare ?? 'No files to share');
        return;
      }
      await Share.shareXFiles(existing.map((p) => XFile(p)).toList(), text: text);
    } catch (e) {
      if (context.mounted) _snack(context, l10n?.couldNotShare(describeError(e, l10n)) ?? 'Could not share');
    }
  }

  static void _snack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}
