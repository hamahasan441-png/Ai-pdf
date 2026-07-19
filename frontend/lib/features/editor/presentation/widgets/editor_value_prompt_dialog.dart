import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

Future<String?> showEditorValuePromptDialog(
  BuildContext context, {
  required String label,
  required TextInputType keyboardType,
  required Widget leading,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          leading,
          const SizedBox(width: 8),
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: AppLocalizations.of(ctx)!.typeHere,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(ctx)!.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(AppLocalizations.of(ctx)!.add)),
      ],
    ),
  );
}
