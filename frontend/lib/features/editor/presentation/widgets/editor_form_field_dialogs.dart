import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';

/// Asks for the text of form field [field]. Returns null when cancelled.
Future<String?> showFormTextDialog(BuildContext context, {required AcroField field, required String initial}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _FormTextDialog(field: field, initial: initial),
  );
}

class _FormTextDialog extends StatefulWidget {
  final AcroField field;
  final String initial;

  const _FormTextDialog({required this.field, required this.initial});

  @override
  State<_FormTextDialog> createState() => _FormTextDialogState();
}

class _FormTextDialogState extends State<_FormTextDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final max = f.maxLen;
    return AlertDialog(
      title: Text(f.name),
      content: TextField(
        controller: _c,
        autofocus: true,
        minLines: f.multiline ? 3 : 1,
        maxLines: f.multiline ? 8 : 1,
        maxLength: max != null && max > 0 ? max : null,
        maxLengthEnforcement: MaxLengthEnforcement.enforced,
        keyboardType: f.multiline ? TextInputType.multiline : TextInputType.text,
        textInputAction: f.multiline ? TextInputAction.newline : TextInputAction.done,
        onSubmitted: f.multiline ? null : (v) => Navigator.pop(context, v),
        decoration: const InputDecoration(border: OutlineInputBorder()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _c.text),
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }
}

/// Lets the user pick the value of choice field [field]. Returns a String
/// for a single choice, a List<String> for a multiple choice, or null when
/// cancelled. An editable combo box also offers typing a value.
Future<Object?> showFormChoiceSheet(BuildContext context, {required AcroField field, required Object current}) {
  return showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ChoiceSheet(field: field, current: current),
  );
}

class _ChoiceSheet extends StatefulWidget {
  final AcroField field;
  final Object current;

  const _ChoiceSheet({required this.field, required this.current});

  @override
  State<_ChoiceSheet> createState() => _ChoiceSheetState();
}

class _ChoiceSheetState extends State<_ChoiceSheet> {
  late final Set<String> _picked = {
    if (widget.current is List) ...(widget.current as List).map((v) => '$v') else '${widget.current}',
  };

  @override
  Widget build(BuildContext context) {
    final f = widget.field;
    final options = f.options;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(f.name, style: Theme.of(context).textTheme.titleMedium),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final (export, shown) in options)
                    if (f.multiSelect)
                      CheckboxListTile(
                        value: _picked.contains(export),
                        title: Text(shown),
                        onChanged: (on) => setState(() => on == true ? _picked.add(export) : _picked.remove(export)),
                      )
                    else
                      ListTile(
                        title: Text(shown),
                        leading: Icon(
                          _picked.contains(export) ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        ),
                        onTap: () => Navigator.pop(context, export),
                      ),
                  if (f.editableCombo)
                    ListTile(
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(AppLocalizations.of(context)!.formTypeValue),
                      onTap: () async {
                        final typed = await showFormTextDialog(
                          context,
                          field: f,
                          initial: widget.current is String ? widget.current as String : '',
                        );
                        if (typed != null && context.mounted) Navigator.pop(context, typed);
                      },
                    ),
                ],
              ),
            ),
            if (f.multiSelect)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, [
                    for (final (export, _) in options)
                      if (_picked.contains(export)) export,
                  ]),
                  child: Text(MaterialLocalizations.of(context).okButtonLabel),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
