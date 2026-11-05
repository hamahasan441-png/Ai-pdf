import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/features/editor/data/page_dressing.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_design.dart';

/// Header or footer: three zones, skip the first page, and the Bates
/// prefix FlexiPDF prints in the margin. Empty zones are removed.
Future<RunningEdgeDraft?> showRunningLineSheet(
  BuildContext context, {
  required RunningEdge edge,
  required RunningEdgeDraft initial,
}) {
  return showModalBottomSheet<RunningEdgeDraft>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(EditorChrome.radiusSheet)),
    ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: _RunningLineSheet(edge: edge, initial: initial),
    ),
  );
}

class _RunningLineSheet extends StatefulWidget {
  final RunningEdge edge;
  final RunningEdgeDraft initial;

  const _RunningLineSheet({required this.edge, required this.initial});

  @override
  State<_RunningLineSheet> createState() => _RunningLineSheetState();
}

class _RunningLineSheetState extends State<_RunningLineSheet> {
  late final TextEditingController _left;
  late final TextEditingController _center;
  late final TextEditingController _right;
  late final TextEditingController _prefix;
  late final TextEditingController _start;
  late bool _skipFirst;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _left = TextEditingController(text: initial.left);
    _center = TextEditingController(text: initial.center);
    _right = TextEditingController(text: initial.right);
    _prefix = TextEditingController(text: initial.batesPrefix);
    _start = TextEditingController(text: '${initial.batesStart}');
    _skipFirst = initial.skipFirst;
  }

  @override
  void dispose() {
    _left.dispose();
    _center.dispose();
    _right.dispose();
    _prefix.dispose();
    _start.dispose();
    super.dispose();
  }

  RunningEdgeDraft _draft({bool clear = false}) {
    final start = int.tryParse(_start.text.trim());
    return RunningEdgeDraft(
      left: clear ? '' : _left.text,
      center: clear ? '' : _center.text,
      right: clear ? '' : _right.text,
      skipFirst: _skipFirst,
      batesPrefix: _prefix.text.trim(),
      batesStart: start == null ? widget.initial.batesStart : start,
      batesDigits: widget.initial.batesDigits,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final title = widget.edge == RunningEdge.header ? l10n.addHeader : l10n.addFooter;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(l10n.runningTokens, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            _field(l10n.runningLeft, _left),
            _field(l10n.runningCenter, _center),
            _field(l10n.runningRight, _right),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.skipFirstPage),
              value: _skipFirst,
              onChanged: (v) => setState(() => _skipFirst = v),
            ),
            Row(
              children: [
                Expanded(child: _field(l10n.batesPrefix, _prefix)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 88,
                  child: _field(
                    l10n.bates,
                    _start,
                    keyboard: TextInputType.number,
                    digits: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
                TextButton(onPressed: () => Navigator.pop(context, _draft(clear: true)), child: Text(l10n.remove)),
                const Spacer(),
                FilledButton(onPressed: () => Navigator.pop(context, _draft()), child: Text(l10n.add)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType keyboard = TextInputType.text,
    bool digits = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        textInputAction: TextInputAction.next,
        inputFormatters: digits ? [FilteringTextInputFormatter.digitsOnly] : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }
}
