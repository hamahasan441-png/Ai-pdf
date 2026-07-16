import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/offline_pdf_service.dart';
import '../widgets/result_sheet.dart';

/// PDF → Images — fully offline. Exports every page of a PDF as a JPG or PNG
/// image on-device, then lets the user save/share the results.
class PdfToImagesScreen extends StatefulWidget {
  const PdfToImagesScreen({super.key});
  @override
  State<PdfToImagesScreen> createState() => _PdfToImagesScreenState();
}

class _PdfToImagesScreenState extends State<PdfToImagesScreen> {
  String? _filePath;
  bool _busy = false;
  bool _png = false;
  List<String>? _outputs;

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    setState(() {
      _filePath = path;
      _outputs = null;
    });
  }

  Future<void> _convert() async {
    if (_filePath == null) return;
    setState(() => _busy = true);
    try {
      final outputs =
          await OfflinePdfService.instance.pdfToImages(_filePath!, png: _png);
      setState(() => _outputs = outputs);
      if (mounted) {
        if (outputs.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No pages could be exported')),
          );
        } else {
          await showResultSheet(
            context,
            paths: outputs,
            title: 'Exported ${outputs.length} image${outputs.length == 1 ? '' : 's'}',
            subtitle: _png ? 'PNG pages' : 'JPG pages',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('PDF to Images')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _busy ? null : _pick,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(
                      color: _filePath != null ? cs.primary : cs.outlineVariant,
                      width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(children: [
                  Icon(_filePath == null ? Icons.upload_file : Icons.picture_as_pdf,
                      size: 48, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    _filePath == null
                        ? 'Tap to choose a PDF'
                        : _filePath!.split('/').last,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('Each page becomes an image',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            Row(children: [
              const Text('Format', style: TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('JPG')),
                  ButtonSegment(value: true, label: Text('PNG')),
                ],
                selected: {_png},
                onSelectionChanged: _busy
                    ? null
                    : (s) => setState(() => _png = s.first),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              _png
                  ? 'PNG: lossless, larger files'
                  : 'JPG: smaller files, great for sharing',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
            if (_outputs != null && _outputs!.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Icon(Icons.check_circle, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Exported ${_outputs!.length} image${_outputs!.length == 1 ? '' : 's'}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => showResultSheet(
                  context,
                  paths: _outputs!,
                  title: 'Exported ${_outputs!.length} images',
                  subtitle: _png ? 'PNG pages' : 'JPG pages',
                ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Save / Share'),
              ),
            ],
            const Spacer(),
            FilledButton.icon(
              onPressed: (_filePath == null || _busy) ? null : _convert,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.image_outlined),
              label: Text(_busy ? 'Exporting...' : 'Export to Images'),
            ),
          ],
        ),
      ),
    );
  }
}
