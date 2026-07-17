import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../core/services/ocr_service.dart';
import '../../../core/services/user_profile_service.dart';
import '../services/smart_form_filler.dart';
import 'pick_edit_screen.dart';

/// Offline Smart Form Filler — no AI API, everything on-device.
///
/// Two steps:
///   1. Upload the blank FORM (PDF or photo).
///   2. Upload an INFO document that contains your details (ID, certificate,
///      a previous form, a CV…).
/// The app OCRs both, understands the form's fields (German + English), pulls
/// the matching values out of your info document, and opens the editor with the
/// answers already placed so you can review, adjust and export.
class SmartFillScreen extends StatefulWidget {
  const SmartFillScreen({super.key});

  @override
  State<SmartFillScreen> createState() => _SmartFillScreenState();
}

class _SmartFillScreenState extends State<SmartFillScreen> {
  static const int _maxPages = 15;
  static const double _renderMaxEdge = 1400;

  String? _formPath;
  String? _formName;
  String? _infoPath;
  String? _infoName;
  bool _busy = false;
  String? _status;
  String? _error;

  Future<void> _pickForm() async {
    final picked = await _pickFile();
    if (picked == null) return;
    setState(() {
      _formPath = picked.$1;
      _formName = picked.$2;
      _error = null;
    });
  }

  Future<void> _pickInfo() async {
    final picked = await _pickFile();
    if (picked == null) return;
    setState(() {
      _infoPath = picked.$1;
      _infoName = picked.$2;
      _error = null;
    });
  }

  Future<(String, String)?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.first.path;
    if (path == null) return null;
    return (path, result.files.first.name);
  }

  Future<void> _run() async {
    final formPath = _formPath;
    final infoPath = _infoPath;
    if (formPath == null || infoPath == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Reading the form…';
    });
    try {
      final formPages = await _ocrDocument(formPath);
      if (!mounted) return;
      setState(() => _status = 'Reading your info…');
      final infoPages = await _ocrDocument(infoPath);

      await UserProfileService.instance.load();
      final profile = UserProfileService.instance.data;

      if (!mounted) return;
      setState(() => _status = 'Matching fields…');
      final info = SmartFormFiller.extractInfo(infoPages);
      final fields = SmartFormFiller.fillForm(formPages, info, profile);

      if (!mounted) return;
      if (fields.isEmpty) {
        setState(() => _error =
            'Couldn\'t confidently match any fields. Make sure the info document '
            'is clear and readable, or open the form in the editor and use '
            'Smart Fill / Auto-fill to place values manually.');
        return;
      }

      final placed = fields.length;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            PickEditScreen(initialPath: formPath, initialFields: fields),
      ));
      if (mounted) {
        setState(() => _status = 'Placed $placed value(s) — review and export.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Render a PDF/image to page images and OCR each, fully on-device.
  Future<List<OcrResult>> _ocrDocument(String path) async {
    final ocr = OcrService();
    final results = <OcrResult>[];
    try {
      if (path.toLowerCase().endsWith('.pdf')) {
        final tmp = await getTemporaryDirectory();
        final stamp = DateTime.now().microsecondsSinceEpoch;
        final doc = await pdfx.PdfDocument.openFile(path);
        try {
          final count = doc.pagesCount < _maxPages ? doc.pagesCount : _maxPages;
          for (var i = 1; i <= count; i++) {
            final page = await doc.getPage(i);
            try {
              final longEdge =
                  page.width > page.height ? page.width : page.height;
              final scale =
                  longEdge > _renderMaxEdge ? _renderMaxEdge / longEdge : 1.0;
              final img = await page.render(
                width: page.width * scale,
                height: page.height * scale,
                format: pdfx.PdfPageImageFormat.jpeg,
                backgroundColor: '#FFFFFF',
              );
              final bytes = img?.bytes;
              if (bytes != null) {
                final p = '${tmp.path}/sf_${stamp}_$i.jpg';
                await File(p).writeAsBytes(bytes);
                results.add(await ocr.recognize(p));
                try {
                  await File(p).delete();
                } catch (_) {}
              } else {
                results.add(const OcrResult('', []));
              }
            } finally {
              await page.close();
            }
          }
        } finally {
          await doc.close();
        }
      } else {
        results.add(await ocr.recognize(path));
      }
    } finally {
      await ocr.dispose();
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = _formPath != null && _infoPath != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Smart Form Filler')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.35),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Icon(Icons.offline_bolt, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Fully on-device — no internet, no AI account. '
                  'Step 1: choose the blank form. Step 2: choose a document with '
                  'your info (ID, certificate, a previous form). It fills the form '
                  'for you to review.',
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          _stepCard(
            cs,
            step: '1',
            icon: Icons.description_outlined,
            title: 'The form to fill',
            fileName: _formName,
            actionLabel: _formName == null ? 'Choose form' : 'Change form',
            onTap: _busy ? null : _pickForm,
          ),
          const SizedBox(height: 12),
          _stepCard(
            cs,
            step: '2',
            icon: Icons.badge_outlined,
            title: 'Your info document',
            fileName: _infoName,
            actionLabel: _infoName == null ? 'Choose info' : 'Change info',
            onTap: _busy ? null : _pickInfo,
          ),
          const SizedBox(height: 20),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.error_outline, size: 18, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: TextStyle(color: cs.onErrorContainer, fontSize: 13)),
                ),
              ]),
            ),
          FilledButton.icon(
            onPressed: ready && !_busy ? _run : null,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_fix_high),
            label: Text(_busy ? (_status ?? 'Working…') : 'Fill the form'),
          ),
          if (!_busy && _status != null) ...[
            const SizedBox(height: 10),
            Text(_status!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _stepCard(
    ColorScheme cs, {
    required String step,
    required IconData icon,
    required String title,
    required String? fileName,
    required String actionLabel,
    required VoidCallback? onTap,
  }) {
    final chosen = fileName != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: chosen ? cs.primary : cs.outlineVariant,
              width: chosen ? 1.5 : 1),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: cs.primary,
            child: Text(step,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  fileName ?? 'Not chosen yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: chosen ? cs.primary : cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(actionLabel,
              style: TextStyle(
                  color: cs.primary, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}
