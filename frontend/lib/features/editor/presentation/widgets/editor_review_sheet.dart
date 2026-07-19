import 'package:ai_pdf/features/tools/models/filled_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// A lightweight review sheet for the editor's integrated Smart Fill.
/// Shows matched fields with checkboxes and edit, returns confirmed list.
class EditorReviewSheet extends StatefulWidget {
  final List<FilledField> fields;

  const EditorReviewSheet({super.key, required this.fields});

  @override
  State<EditorReviewSheet> createState() => _EditorReviewSheetState();
}

class _EditorReviewSheetState extends State<EditorReviewSheet> {
  late List<bool> _checked;
  late List<FilledField> _fields;

  @override
  void initState() {
    super.initState();
    _fields = List.of(widget.fields);
    _checked = List.filled(_fields.length, true);
  }

  void _editField(int i) async {
    final ctrl = TextEditingController(text: _fields[i].text);
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fields[i].field.isNotEmpty ? _fields[i].field : l10n.editText),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: l10n.typeHere,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(l10n.ok)),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      setState(() => _fields[i] = _fields[i].withText(result.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final count = _checked.where((c) => c).length;
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(Icons.psychology, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.reviewBeforePlacing,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                l10n.editAnyValue,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _fields.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final f = _fields[i];
                  return ListTile(
                    leading: Checkbox(
                      value: _checked[i],
                      onChanged: (v) => setState(() => _checked[i] = v ?? false),
                    ),
                    title: Text(
                      f.field.isNotEmpty ? f.field : f.anchor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _checked[i] ? cs.onSurface : cs.outline,
                      ),
                    ),
                    subtitle: Text(
                      f.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: _checked[i] ? cs.primary : cs.outline,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (f.uncertain)
                          Tooltip(
                            message: l10n.smartFillUncertain,
                            child: Icon(Icons.warning_amber_rounded, size: 18, color: cs.error),
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: l10n.editText,
                          onPressed: _checked[i] ? () => _editField(i) : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: count > 0
                    ? () {
                        final result = <FilledField>[];
                        for (var i = 0; i < _fields.length; i++) {
                          if (_checked[i]) result.add(_fields[i]);
                        }
                        Navigator.pop(context, result);
                      }
                    : null,
                icon: const Icon(Icons.check),
                label: Text(l10n.placeNValues(count)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
