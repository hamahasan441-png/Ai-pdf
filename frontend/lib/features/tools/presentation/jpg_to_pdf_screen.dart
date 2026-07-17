import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/offline_pdf_service.dart';
import '../widgets/result_sheet.dart';

/// JPG to PDF - fully offline. Pick images, convert, save/share.
class JpgToPdfScreen extends StatefulWidget {
  const JpgToPdfScreen({super.key});
  @override
  State<JpgToPdfScreen> createState() => _JpgToPdfScreenState();
}

class _JpgToPdfScreenState extends State<JpgToPdfScreen> {
  final List<String> _images = [];
  bool _busy = false;
  String? _outputPath;

  Future<void> _pickImages() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result != null) {
      setState(() {
        _images.addAll(result.paths.whereType<String>());
        _outputPath = null;
      });
    }
  }

  Future<void> _convert() async {
    if (_images.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final path = await OfflinePdfService.instance.imagesToPdf(_images);
      setState(() => _outputPath = path);
      if (mounted) {
        await showResultSheet(context,
            paths: [path],
            title: l10n.pdfCreated,
            subtitle: l10n.imagesConverted(_images.length));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.conversionFailed(e.toString()))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.toolJpgToPdf),
        actions: [
          if (_outputPath != null)
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              tooltip: l10n.saveShare,
              onPressed: () => showResultSheet(context, paths: [_outputPath!], title: l10n.pdfReady),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _images.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 72, color: cs.outline),
                        const SizedBox(height: 16),
                        Text(l10n.noImagesSelected, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(l10n.tapToChooseImages, style: TextStyle(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(16),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8),
                    itemCount: _images.length,
                    itemBuilder: (_, i) => Stack(
                      fit: StackFit.expand,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(File(_images[i]), fit: BoxFit.cover),
                        ),
                        Positioned(
                          top: 2, right: 2,
                          child: GestureDetector(
                            onTap: () => setState(() => _images.removeAt(i)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _pickImages,
                      icon: const Icon(Icons.add),
                      label: Text(l10n.addImages),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (_images.isEmpty || _busy) ? null : _convert,
                      icon: _busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.picture_as_pdf),
                      label: Text(_busy ? l10n.converting : l10n.createPdf),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
