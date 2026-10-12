import 'package:flutter/material.dart';

/// Double confirmation sheet for true redaction — E6.3B / E1.7 Phase 6.
enum RedactionConfirmResult { cancelled, confirmed }

/// Only valid after a backend redaction call returns a new PDF.
/// The editor Redact tool burns a black cover into the exported page image
/// and does not rewrite the original file in place.
Future<RedactionConfirmResult?> showEditorRedactionConfirmSheet(
  BuildContext context, {
  required int areaCount,
}) {
  return showModalBottomSheet<RedactionConfirmResult>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RedactionConfirmSheet(areaCount: areaCount),
  );
}

class _RedactionConfirmSheet extends StatefulWidget {
  final int areaCount;
  const _RedactionConfirmSheet({required this.areaCount});

  @override
  State<_RedactionConfirmSheet> createState() => _RedactionConfirmSheetState();
}

class _RedactionConfirmSheetState extends State<_RedactionConfirmSheet> {
  int _step = 1;
  bool _understandChecked = false;
  bool _understandChecked2 = false;
  final TextEditingController _typedController = TextEditingController();
  bool get _typedCorrect => _typedController.text.trim().toUpperCase() == 'REDACT';

  @override
  void dispose() {
    _typedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_step == 1) return _buildStep1(cs);
    return _buildStep2(cs);
  }

  Widget _buildStep1(ColorScheme cs) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Icon(Icons.warning_amber_rounded, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text('Cover in the export', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: cs.error)),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollCtrl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('You are about to cover ${widget.areaCount} area(s) with a black mark that is burned into the exported page image.', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    _bullet('This is not the same as whiteout. Whiteout is a removable white box. This cover is painted into the exported picture of the page.'),
                    _bullet('The original PDF file is not rewritten. Hidden text inside the original file can still be extracted until you keep only the exported copy.'),
                    _bullet('The app cannot remove text from the PDF content stream, images behind the cover, or document metadata.'),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: cs.errorContainer.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, size: 20, color: cs.onErrorContainer),
                          const SizedBox(width: 8),
                          Expanded(child: Text('A black rectangle in the export is not proof that the original text was removed from the source PDF.', style: TextStyle(fontSize: 11, color: cs.onErrorContainer))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [Checkbox(value: _understandChecked, onChanged: (v) => setState(() => _understandChecked = v ?? false)), const Expanded(child: Text('I understand the cover is burned into the export and the original file is kept', style: TextStyle(fontSize: 12)))]),
            const SizedBox(height: 12),
            Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, RedactionConfirmResult.cancelled), child: const Text('Cancel'))), const SizedBox(width: 12), Expanded(child: FilledButton(onPressed: _understandChecked ? () => setState(() => _step = 2) : null, child: const Text('Continue')))]),
          ],
        ),
      ),
    );
  }

  Widget _buildStep2(ColorScheme cs) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: cs.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Icon(Icons.gavel, size: 48, color: cs.error),
            const SizedBox(height: 12),
            const Text('Final Confirmation', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text('Type "REDACT" to burn the cover into the exported copy of ${widget.areaCount} area(s)', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            TextField(controller: _typedController, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Type REDACT', hintText: 'REDACT'), onChanged: (_) => setState(() {}), textCapitalization: TextCapitalization.characters),
            const SizedBox(height: 12),
            Row(children: [Checkbox(value: _understandChecked2, onChanged: (v) => setState(() => _understandChecked2 = v ?? false)), const Expanded(child: Text('I have verified the redaction areas and understand this cannot be undone', style: TextStyle(fontSize: 11)))]),
            const Spacer(),
            Row(children: [Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, RedactionConfirmResult.cancelled), child: const Text('Cancel'))), const SizedBox(width: 12), Expanded(child: FilledButton(style: FilledButton.styleFrom(backgroundColor: cs.error), onPressed: _typedCorrect && _understandChecked2 ? () => Navigator.pop(context, RedactionConfirmResult.confirmed) : null, child: const Text('REDACT NOW')))]),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)), Expanded(child: Text(text, style: const TextStyle(fontSize: 13)))]));
}
