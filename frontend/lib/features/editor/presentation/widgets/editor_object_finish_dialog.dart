import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/data/object_arrange.dart';

/// Which edge of the page the selected mark should meet.
Future<PageEdge?> showEditorPageAlignDialog(BuildContext context) {
  return showDialog<PageEdge>(
    context: context,
    builder: (ctx) {
      final l10n = AppLocalizations.of(ctx)!;
      Widget tile(PageEdge edge, IconData icon, String label) => ListTile(
            dense: true,
            leading: Icon(icon),
            title: Text(label),
            onTap: () => Navigator.pop(ctx, edge),
          );
      return AlertDialog(
        title: Text(l10n.alignToPage),
        contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              tile(PageEdge.left, Icons.align_horizontal_left, l10n.alignLeft),
              tile(PageEdge.hCenter, Icons.align_horizontal_center, l10n.alignCenter),
              tile(PageEdge.right, Icons.align_horizontal_right, l10n.alignRight),
              tile(PageEdge.top, Icons.align_vertical_top, l10n.alignTop),
              tile(PageEdge.vCenter, Icons.align_vertical_center, l10n.alignMiddle),
              tile(PageEdge.bottom, Icons.align_vertical_bottom, l10n.alignBottom),
            ],
          ),
        ),
      );
    },
  );
}

/// Opacity of whatever is selected, as a percent. Null if cancelled.
Future<double?> showEditorOpacityDialog(BuildContext context, {required double opacity}) {
  var value = opacity.clamp(0.1, 1.0);
  return showDialog<double>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final l10n = AppLocalizations.of(ctx)!;
        return AlertDialog(
          title: Text(l10n.opacity),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${(value * 100).round()}%'),
              Slider(
                value: value,
                min: 0.1,
                max: 1,
                onChanged: (v) => setLocal(() => value = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
            FilledButton(onPressed: () => Navigator.pop(ctx, value), child: Text(l10n.done)),
          ],
        );
      },
    ),
  );
}
