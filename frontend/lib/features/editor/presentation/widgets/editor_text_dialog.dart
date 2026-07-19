import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class TextAnnotationEditResult {
  final String action; // save | delete
  final String text;
  final double size;
  final bool bold;
  final bool italic;
  final bool underline;
  final String? fontFamily;
  final Color color;

  const TextAnnotationEditResult({
    required this.action,
    required this.text,
    required this.size,
    required this.bold,
    required this.italic,
    required this.underline,
    required this.fontFamily,
    required this.color,
  });

  bool get isDelete => action == 'delete';
}

Future<TextAnnotationEditResult?> showEditorTextDialog(
  BuildContext context, {
  required bool isNew,
  required String text,
  required double size,
  required bool bold,
  required bool italic,
  required bool underline,
  required String? fontFamily,
  required Color color,
}) async {
  final ctrl = TextEditingController(text: text);
  double localSize = size;
  bool localBold = bold;
  bool localItalic = italic;
  bool localUnderline = underline;
  String? localFont = fontFamily;
  Color localColor = color;

  return showDialog<TextAnnotationEditResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text(isNew ? 'Add Text' : 'Edit Text'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(ctx)!.typeText,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(AppLocalizations.of(ctx)!.sizeLabel),
                Expanded(
                  child: Slider(
                    value: localSize,
                    min: 0.015,
                    max: 0.08,
                    onChanged: (v) => setLocal(() => localSize = v),
                  ),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(ctx)!.bold,
                  isSelected: localBold,
                  icon: const Icon(Icons.format_bold),
                  onPressed: () => setLocal(() => localBold = !localBold),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(ctx)!.italic,
                  isSelected: localItalic,
                  icon: const Icon(Icons.format_italic),
                  onPressed: () => setLocal(() => localItalic = !localItalic),
                ),
                IconButton(
                  tooltip: AppLocalizations.of(ctx)!.underline,
                  isSelected: localUnderline,
                  icon: const Icon(Icons.format_underlined),
                  onPressed: () => setLocal(() => localUnderline = !localUnderline),
                ),
              ],
            ),
            Row(
              children: [
                Text(AppLocalizations.of(ctx)!.font),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButton<String?>(
                    value: localFont,
                    isExpanded: true,
                    items: [
                      DropdownMenuItem(value: null, child: Text(AppLocalizations.of(ctx)!.fontDefault)),
                      const DropdownMenuItem(
                        value: 'serif',
                        child: Text('Serif', style: TextStyle(fontFamily: 'serif')),
                      ),
                      const DropdownMenuItem(
                        value: 'monospace',
                        child: Text('Mono', style: TextStyle(fontFamily: 'monospace')),
                      ),
                    ],
                    onChanged: (v) => setLocal(() => localFont = v),
                  ),
                ),
              ],
            ),
            Row(
              children: [Colors.red, Colors.blue, Colors.black, Colors.green, Colors.orange, Colors.purple]
                  .map((c) => GestureDetector(
                        onTap: () => setLocal(() => localColor = c),
                        child: Container(
                          width: 28,
                          height: 28,
                          margin: const EdgeInsets.only(right: 8, top: 4),
                          decoration: BoxDecoration(
                            color: c,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: localColor == c ? Colors.blueAccent : Colors.grey.shade400,
                              width: localColor == c ? 3 : 1,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
        actions: [
          if (!isNew)
            TextButton(
              onPressed: () => Navigator.pop(
                ctx,
                TextAnnotationEditResult(
                  action: 'delete',
                  text: ctrl.text,
                  size: localSize,
                  bold: localBold,
                  italic: localItalic,
                  underline: localUnderline,
                  fontFamily: localFont,
                  color: localColor,
                ),
              ),
              child: Text(AppLocalizations.of(ctx)!.delete, style: const TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(ctx)!.cancel)),
          FilledButton(
            onPressed: () => Navigator.pop(
              ctx,
              TextAnnotationEditResult(
                action: 'save',
                text: ctrl.text,
                size: localSize,
                bold: localBold,
                italic: localItalic,
                underline: localUnderline,
                fontFamily: localFont,
                color: localColor,
              ),
            ),
            child: Text(AppLocalizations.of(ctx)!.ok),
          ),
        ],
      ),
    ),
  );
}
