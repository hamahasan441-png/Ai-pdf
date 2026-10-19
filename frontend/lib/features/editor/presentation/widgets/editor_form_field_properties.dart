import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/domain/entities/form_field_annotation.dart';

/// The kinds offered when adding a field, in menu order.
const addableFieldKinds = [
  FormFieldKind.text,
  FormFieldKind.number,
  FormFieldKind.date,
  FormFieldKind.email,
  FormFieldKind.checkbox,
  FormFieldKind.combobox,
  FormFieldKind.signature,
];

String fieldKindLabel(AppLocalizations? l10n, FormFieldKind kind) => switch (kind) {
      FormFieldKind.number => l10n?.fieldKindNumber ?? 'Number',
      FormFieldKind.date => l10n?.fieldKindDate ?? 'Date',
      FormFieldKind.email => l10n?.fieldKindEmail ?? 'E-mail',
      FormFieldKind.phone => l10n?.fieldKindPhone ?? 'Phone',
      FormFieldKind.checkbox || FormFieldKind.radio => l10n?.fieldKindCheckbox ?? 'Check box',
      FormFieldKind.combobox => l10n?.fieldKindDropdown ?? 'Drop-down list',
      FormFieldKind.signature => l10n?.fieldKindSignature ?? 'Signature',
      _ => l10n?.fieldKindText ?? 'Text',
    };

IconData fieldKindIcon(FormFieldKind kind) => switch (kind) {
      FormFieldKind.number => Icons.pin_outlined,
      FormFieldKind.date => Icons.event_outlined,
      FormFieldKind.email => Icons.alternate_email,
      FormFieldKind.phone => Icons.phone_outlined,
      FormFieldKind.checkbox || FormFieldKind.radio => Icons.check_box_outlined,
      FormFieldKind.combobox => Icons.arrow_drop_down_circle_outlined,
      FormFieldKind.signature => Icons.draw_outlined,
      _ => Icons.short_text,
    };

/// Asks which kind of field to add.
Future<FormFieldKind?> showAddFormFieldSheet(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  return showModalBottomSheet<FormFieldKind>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text(l10n?.addFormField ?? 'Add form field', style: Theme.of(ctx).textTheme.titleMedium)),
            for (final k in addableFieldKinds)
              ListTile(
                leading: Icon(fieldKindIcon(k)),
                title: Text(fieldKindLabel(l10n, k)),
                onTap: () => Navigator.pop(ctx, k),
              ),
          ],
        ),
      ),
    ),
  );
}

/// A new field of [kind] in the middle of the page, sized for its kind on a
/// page [aspect] (width / height) wide.
FormFieldAnnotation newFormField(FormFieldKind kind, {required String label, double aspect = 0.7}) {
  final (double w, double h) = switch (kind) {
    FormFieldKind.checkbox || FormFieldKind.radio => (0.035, 0.035 * aspect),
    FormFieldKind.signature => (0.35, 0.06),
    FormFieldKind.combobox => (0.3, 0.03),
    _ => (0.35, 0.03),
  };
  return FormFieldAnnotation(
    pos: Offset(0.5 - w / 2, 0.5 - h / 2),
    width: w,
    height: h,
    fieldKind: kind,
    label: label,
    options: kind == FormFieldKind.combobox ? const ['1', '2', '3'] : const [],
  );
}

/// Edits [field]'s name, required flag and value or options. Changes apply
/// to [field] only on Save; returns whether they did.
Future<bool> showFormFieldPropertiesDialog(BuildContext context, FormFieldAnnotation field) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => _FieldPropertiesDialog(field: field),
  );
  return saved == true;
}

class _FieldPropertiesDialog extends StatefulWidget {
  final FormFieldAnnotation field;

  const _FieldPropertiesDialog({required this.field});

  @override
  State<_FieldPropertiesDialog> createState() => _FieldPropertiesDialogState();
}

class _FieldPropertiesDialogState extends State<_FieldPropertiesDialog> {
  late final _name = TextEditingController(text: widget.field.label);
  late final _value = TextEditingController(text: widget.field.value);
  late final _options = TextEditingController(text: widget.field.options.join('\n'));
  late bool _required = widget.field.required;
  late bool _checked = widget.field.checked;
  late bool _multiline = widget.field.multiline;

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _options.dispose();
    super.dispose();
  }

  List<String> get _opts => [for (final o in _options.text.split('\n')) if (o.trim().isNotEmpty) o.trim()];

  void _save() {
    final field = widget.field;
    if (_name.text.trim().isNotEmpty) field.label = _name.text.trim();
    field.required = _required;
    field.checked = _checked;
    field.multiline = _multiline;
    if (field.fieldKind == FormFieldKind.combobox) {
      field.options = _opts;
      field.value = field.options.contains(_value.text) ? _value.text : '';
    } else if (!field.isCheckable && field.fieldKind != FormFieldKind.signature) {
      field.value = _multiline ? _value.text : _value.text.replaceAll('\n', ' ');
    }
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final field = widget.field;
    final opts = _opts;
    final textKind =
        !field.isCheckable && field.fieldKind != FormFieldKind.combobox && field.fieldKind != FormFieldKind.signature;
    return AlertDialog(
      title: Row(children: [
        Icon(fieldKindIcon(field.fieldKind)),
        const SizedBox(width: 8),
        Expanded(child: Text(fieldKindLabel(l10n, field.fieldKind))),
      ]),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('fieldName'),
              controller: _name,
              decoration: InputDecoration(labelText: l10n?.fieldName ?? 'Field name'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n?.fieldRequired ?? 'Required'),
              value: _required,
              onChanged: (v) => setState(() => _required = v),
            ),
            if (textKind) ...[
              TextField(
                key: const ValueKey('fieldValue'),
                controller: _value,
                maxLines: _multiline ? 3 : 1,
                keyboardType: switch (field.fieldKind) {
                  FormFieldKind.number => TextInputType.number,
                  FormFieldKind.email => TextInputType.emailAddress,
                  FormFieldKind.phone => TextInputType.phone,
                  FormFieldKind.date => TextInputType.datetime,
                  _ => TextInputType.text,
                },
                decoration: InputDecoration(labelText: l10n?.fieldDefaultValue ?? 'Value'),
              ),
              if (field.fieldKind == FormFieldKind.text)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n?.fieldMultiline ?? 'Several lines'),
                  value: _multiline,
                  onChanged: (v) => setState(() => _multiline = v),
                ),
            ],
            if (field.isCheckable)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n?.fieldChecked ?? 'Ticked'),
                value: _checked,
                onChanged: (v) => setState(() => _checked = v),
              ),
            if (field.fieldKind == FormFieldKind.combobox) ...[
              TextField(
                key: const ValueKey('fieldOptions'),
                controller: _options,
                minLines: 3,
                maxLines: 6,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: l10n?.fieldOptions ?? 'Options, one per line'),
              ),
              DropdownButtonFormField<String>(
                key: ValueKey(opts.join('\n')),
                value: opts.contains(_value.text) ? _value.text : '',
                decoration: InputDecoration(labelText: l10n?.fieldDefaultValue ?? 'Value'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('—')),
                  for (final o in opts.toSet()) DropdownMenuItem(value: o, child: Text(o)),
                ],
                onChanged: (v) => setState(() => _value.text = v ?? ''),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n?.cancel ?? 'Cancel')),
        FilledButton(onPressed: _save, child: Text(l10n?.save ?? 'Save')),
      ],
    );
  }
}
