import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// Before a source-preserving export that has to turn some pages into
/// images. Returns true to continue.
Future<bool> showEditorFlattenNoticeDialog(
  BuildContext context, {
  required List<int> pages,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final list = pages.map((p) => '${p + 1}').join(', ');
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.exportFlattenTitle),
      content: Text(l10n.exportFlattenBody(list)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.exportFlattenContinue),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// The original PDF cannot be kept. Ask before an image-only export, which
/// loses searchable text, links, form fields and bookmarks. Returns true to
/// save as images.
Future<bool> showEditorImageExportFallbackDialog(
  BuildContext context, {
  required String reason,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.exportImageFallbackTitle),
      content: Text(l10n.exportImageFallbackBody(reason)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.exportImageFallbackConfirm),
        ),
      ],
    ),
  );
  return ok ?? false;
}
