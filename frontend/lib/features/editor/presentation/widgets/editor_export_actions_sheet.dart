import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class EditorExportActionResult {
  final String kind; // share | route
  final String? route;
  final String? handoffPath;

  const EditorExportActionResult.share()
      : kind = 'share',
        route = null,
        handoffPath = null;

  const EditorExportActionResult.route(this.route, {this.handoffPath}) : kind = 'route';
}

Future<EditorExportActionResult?> showEditorExportActionsSheet(
  BuildContext context, {
  required String outPath,
}) {
  final l10n = AppLocalizations.of(context)!;
  final cs = Theme.of(context).colorScheme;
  return showModalBottomSheet<EditorExportActionResult>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
            child: Row(children: [
              Icon(Icons.check_circle, color: cs.secondary, size: 22),
              const SizedBox(width: 8),
              Text('Saved', style: Theme.of(ctx).textTheme.titleMedium),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('Do more with your file', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ),
          ListTile(
            leading: Icon(Icons.ios_share, color: cs.primary),
            title: const Text('Share'),
            onTap: () => Navigator.pop(ctx, const EditorExportActionResult.share()),
          ),
          _toolTile(ctx, Icons.compress, l10n.toolCompress, outPath, '/tools/compress'),
          _toolTile(ctx, Icons.sync_alt, l10n.convert, outPath, '/tools/convert'),
          _toolTile(ctx, Icons.collections, l10n.toolPdfToImages, outPath, '/tools/pdf-to-images'),
          _toolTile(ctx, Icons.text_snippet, l10n.toolPdfToText, outPath, '/tools/pdf-to-text'),
          const Divider(height: 1),
          _toolTile(ctx, Icons.grid_view, l10n.tools, null, '/tools'),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

Widget _toolTile(BuildContext ctx, IconData icon, String label, String? handoffPath, String route) {
  final cs = Theme.of(ctx).colorScheme;
  return ListTile(
    leading: Icon(icon, color: cs.primary),
    title: Text(label),
    trailing: const Icon(Icons.chevron_right, size: 20),
    onTap: () => Navigator.pop(ctx, EditorExportActionResult.route(route, handoffPath: handoffPath)),
  );
}
