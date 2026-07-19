import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

Future<String?> showEditorSmartFillSourceSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person),
              title: Text(l10n.aiFillFromProfile),
              subtitle: Text(l10n.aiFillFromProfileDesc),
              onTap: () => Navigator.pop(ctx, 'profile'),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: Text(l10n.aiFillFromDoc),
              subtitle: Text(l10n.aiFillFromDocDesc),
              onTap: () => Navigator.pop(ctx, 'doc'),
            ),
          ],
        ),
      );
    },
  );
}
