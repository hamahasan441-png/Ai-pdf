import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SignatureChoiceResult {
  final String? action; // new | type | saved_i
  final int? deleteIndex;

  const SignatureChoiceResult({this.action, this.deleteIndex});

  bool get isDelete => deleteIndex != null;
}

Future<SignatureChoiceResult?> showEditorSignaturePickerSheet(
  BuildContext context, {
  required int savedSignatureCount,
}) {
  return showModalBottomSheet<SignatureChoiceResult>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.draw),
            title: Text(AppLocalizations.of(ctx)!.drawNewSignature),
            onTap: () => Navigator.pop(ctx, const SignatureChoiceResult(action: 'new')),
          ),
          ListTile(
            leading: const Icon(Icons.keyboard),
            title: Text(AppLocalizations.of(ctx)!.typeSignature),
            onTap: () => Navigator.pop(ctx, const SignatureChoiceResult(action: 'type')),
          ),
          if (savedSignatureCount > 0) const Divider(height: 1),
          ...List.generate(
            savedSignatureCount,
            (i) => ListTile(
              leading: const Icon(Icons.gesture),
              title: Text(AppLocalizations.of(ctx)!.savedSignatureN(i + 1)),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => Navigator.pop(ctx, SignatureChoiceResult(deleteIndex: i)),
              ),
              onTap: () => Navigator.pop(ctx, SignatureChoiceResult(action: 'saved_$i')),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<bool?> showEditorSaveSignatureDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(AppLocalizations.of(ctx)!.saveThisSignature),
      content: Text(AppLocalizations.of(ctx)!.savedSignaturesReused),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(ctx)!.no)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(ctx)!.save)),
      ],
    ),
  );
}
