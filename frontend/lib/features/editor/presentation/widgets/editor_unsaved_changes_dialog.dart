import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

Future<String?> showEditorUnsavedChangesDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(AppLocalizations.of(ctx)!.unsavedChanges),
      content: Text(AppLocalizations.of(ctx)!.unsavedEditsBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'discard'),
          child: Text(AppLocalizations.of(ctx)!.discard),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'save'),
          child: Text(AppLocalizations.of(ctx)!.saveAndExit),
        ),
      ],
    ),
  );
}
