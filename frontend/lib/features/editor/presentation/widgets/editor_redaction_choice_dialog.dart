import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// What the user picked for a drawn redaction box.
enum RedactionChoice { secure, visualCover }

/// Ask before uploading: the app otherwise keeps files on the device.
///
/// Returns null when the dialog is dismissed. [secureAvailable] false hides
/// the upload option (an inserted blank page or an image document has no
/// source PDF page to send).
Future<RedactionChoice?> showEditorRedactionChoiceDialog(
  BuildContext context, {
  required bool secureAvailable,
}) {
  return showDialog<RedactionChoice>(
    context: context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      return AlertDialog(
        title: Text(l10n.redactChoiceTitle),
        content: Text(
          secureAvailable ? l10n.redactChoiceBody : l10n.redactSecureUnavailable,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, RedactionChoice.visualCover),
            child: Text(l10n.redactVisualOnly),
          ),
          if (secureAvailable)
            FilledButton(
              onPressed: () => Navigator.pop(ctx, RedactionChoice.secure),
              child: Text(l10n.redactSecureUpload),
            ),
        ],
      );
    },
  );
}
