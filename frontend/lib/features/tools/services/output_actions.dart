import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Unified output actions for any generated file.
///
/// Big-app standard: after producing a file the user can always
///   - Save it to their device (choose location via the system dialog)
///   - Share it to any app
///   - Preview it in-app
///
/// Every method is wrapped so a failure shows a message instead of crashing.
class OutputActions {
  OutputActions._();

  /// Save a file to a user-chosen location using the system Save dialog.
  static Future<void> save(BuildContext context, String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        _snack(context, 'File no longer exists');
        return;
      }
      final bytes = await file.readAsBytes();
      final name = path.split('/').last;

      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Save to device',
        fileName: name,
        bytes: bytes,
      );

      if (context.mounted) {
        _snack(context, saved != null ? 'Saved to device' : 'Save cancelled');
      }
    } catch (e) {
      if (context.mounted) _snack(context, 'Could not save: $e');
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
