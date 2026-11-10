import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/data/workspace_commands.dart';

/// Asks for the selection's place and size in millimetres. Cancel returns null.
Future<MillimetreBox?> showEditorGeometryDialog(BuildContext context, {required MillimetreBox initial}) {
  return showDialog<MillimetreBox>(
    context: context,
    builder: (ctx) => _GeometryDialog(initial: initial),
  );
}

class _GeometryDialog extends StatefulWidget {
  final MillimetreBox initial;

  const _GeometryDialog({required this.initial});

  @override
  State<_GeometryDialog> createState() => _GeometryDialogState();
}

class _GeometryDialogState extends State<_GeometryDialog> {
  late final TextEditingController _x;
  late final TextEditingController _y;
  late final TextEditingController _w;
  late final TextEditingController _h;
  String? _error;

  @override
  void initState() {
    super.initState();
    _x = TextEditingController(text: formatMillimetres(widget.initial.left));
    _y = TextEditingController(text: formatMillimetres(widget.initial.top));
    _w = TextEditingController(text: formatMillimetres(widget.initial.width));
    _h = TextEditingController(text: formatMillimetres(widget.initial.height));
  }

  @override
  void dispose() {
    _x.dispose();
    _y.dispose();
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  void _submit() {
    final l10n = AppLocalizations.of(context)!;
    final left = parseMillimetres(_x.text);
    final top = parseMillimetres(_y.text);
    final width = parseMillimetres(_w.text);
    final height = parseMillimetres(_h.text);
    if (left == null || top == null || width == null || height == null || width < 0 || height < 0) {
      setState(() => _error = l10n.placeInvalid);
      return;
    }
    Navigator.pop(context, MillimetreBox(left: left, top: top, width: width, height: height));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.placeBySize),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_x, l10n.placeX),
          _field(_y, l10n.placeY),
          _field(_w, l10n.placeWidth),
          _field(_h, l10n.placeHeight),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13)),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: _submit, child: Text(l10n.done)),
      ],
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,-]'))],
        decoration: InputDecoration(
          labelText: label,
          suffixText: 'mm',
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
    );
  }
}
