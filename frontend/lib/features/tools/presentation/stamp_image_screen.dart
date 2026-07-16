import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/offline_pdf_service.dart';
import '../widgets/result_sheet.dart';

/// Stamp Image — overlay a logo, signature, or photo onto a PDF at a chosen
/// position and size. Fully offline. Great for letterheads, stamps, and marks.
class StampImageScreen extends StatefulWidget {
  const StampImageScreen({super.key});
  @override
  State<StampImageScreen> createState() => _StampImageScreenState();
}

class _StampImageScreenState extends State<StampImageScreen> {
  String? _pdfPath;
  String? _imgPath;
  bool _busy = false;
  int _position = 8; // default bottom-right (common for logos/signatures)
  double _size = 0.25;
  bool _firstPageOnly = false;

  Future<void> _pickPdf() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (r == null || r.files.isEmpty) return;
    final p = r.files.first.path;
    if (p == null) return;
    setState(() => _pdfPath = p);
  }

  Future<void> _pickImage() async {
    final r = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['png', 'jpg', 'jpeg']);
    if (r == null || r.files.isEmpty) return;
    final p = r.files.first.path;
    if (p == null) return;
    setState(() => _imgPath = p);
  }

  Future<void> _apply() async {
    if (_pdfPath == null || _imgPath == null) return;
    setState(() => _busy = true);
    try {
      final out = await OfflinePdfService.instance.stampImageOnPdf(
        _pdfPath!,
        _imgPath!,
        position: _position,
        sizePct: _size,
        firstPageOnly: _firstPageOnly,
      );
      if (mounted) {
        await showResultSheet(context,
            paths: [out], title: 'Image stamped', subtitle: 'Applied to PDF');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Stamp Image')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            Expanded(child: _pickTile(cs, 'PDF', _pdfPath, Icons.picture_as_pdf, _pickPdf)),
            const SizedBox(width: 12),
            Expanded(child: _pickTile(cs, 'Image', _imgPath, Icons.image, _pickImage)),
          ]),
          const SizedBox(height: 24),
          const Text('Position', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          _positionGrid(cs),
          const SizedBox(height: 20),
          Row(children: [
            const Text('Size', style: TextStyle(fontWeight: FontWeight.w600)),
            Expanded(
              child: Slider(
                value: _size,
                min: 0.08,
                max: 0.7,
                divisions: 12,
                label: '${(_size * 100).round()}%',
                onChanged: _busy ? null : (v) => setState(() => _size = v),
              ),
            ),
            Text('${(_size * 100).round()}%', style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('First page only'),
            subtitle: const Text('Otherwise, stamp every page'),
            value: _firstPageOnly,
            onChanged: _busy ? null : (v) => setState(() => _firstPageOnly = v),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: (_pdfPath == null || _imgPath == null || _busy) ? null : _apply,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.approval),
            label: Text(_busy ? 'Stamping...' : 'Stamp onto PDF'),
          ),
        ],
      ),
    );
  }

  Widget _pickTile(ColorScheme cs, String label, String? path, IconData icon, VoidCallback onTap) {
    final picked = path != null;
    return InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 120,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: picked ? cs.primary : cs.outlineVariant, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(picked ? icon : Icons.add, size: 32, color: cs.primary),
            const SizedBox(height: 8),
            Text(
              picked ? path.split('/').last : 'Choose $label',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _positionGrid(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: AspectRatio(
        aspectRatio: 1.4,
        child: GridView.count(
          crossAxisCount: 3,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(9, (i) {
            final selected = _position == i;
            return GestureDetector(
              onTap: _busy ? null : () => setState(() => _position = i),
              child: Container(
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: selected ? cs.primary : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  selected ? Icons.check : Icons.crop_square,
                  size: 18,
                  color: selected ? Colors.white : cs.onSurfaceVariant,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
