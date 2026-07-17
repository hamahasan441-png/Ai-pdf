import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../core/services/ocr_service.dart';
import '../widgets/result_sheet.dart';

/// Extract Text (OCR) — offline, on-device text recognition from a PDF or
/// image. Useful for scanned documents. Fully offline (bundled ML Kit model).
class OcrScreen extends StatefulWidget {
  const OcrScreen({super.key});

  @override
  State<OcrScreen> createState() => _OcrScreenState();
}

class _OcrScreenState extends State<OcrScreen> {
  static const double _renderMaxEdge = 1700; // higher res = better OCR

  final _ocr = OcrService();
  bool _busy = false;
  String _status = '';
  String? _fileName;
  String _text = '';

  @override
  void dispose() {
    _ocr.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    final l10n = AppLocalizations.of(context)!;

    setState(() {
      _busy = true;
      _text = '';
      _status = l10n.reading;
      _fileName = result.files.first.name;
    });

    try {
      final buffer = StringBuffer();
      if (path.toLowerCase().endsWith('.pdf')) {
        final tmpDir = await getTemporaryDirectory();
        final doc = await pdfx.PdfDocument.openFile(path);
        try {
          for (var i = 1; i <= doc.pagesCount; i++) {
            setState(() => _status = l10n.readingPageOf(i, doc.pagesCount));
            final page = await doc.getPage(i);
            String? tmpPath;
            try {
              final longEdge = page.width > page.height ? page.width : page.height;
              final scale = longEdge > _renderMaxEdge ? _renderMaxEdge / longEdge : 1.0;
              final img = await page.render(
                width: page.width * scale,
                height: page.height * scale,
                format: pdfx.PdfPageImageFormat.jpeg,
                backgroundColor: '#FFFFFF',
              );
              if (img?.bytes != null) {
                final f = File('${tmpDir.path}/ocr_${DateTime.now().microsecondsSinceEpoch}_$i.jpg');
                await f.writeAsBytes(img!.bytes);
                tmpPath = f.path;
              }
            } finally {
              await page.close();
            }
            if (tmpPath != null) {
              final t = await _ocr.recognizeText(tmpPath);
              if (t.trim().isNotEmpty) {
                if (buffer.isNotEmpty) buffer.write('\n\n');
                buffer.write('--- Page $i ---\n$t');
              }
              try {
                await File(tmpPath).delete();
              } catch (_) {}
            }
            await Future<void>.delayed(Duration.zero);
          }
        } finally {
          await doc.close();
        }
      } else {
        setState(() => _status = l10n.readingImage);
        buffer.write(await _ocr.recognizeText(path));
      }

      final text = buffer.toString().trim();
      setState(() {
        _text = text.isEmpty ? l10n.noTextFound : text;
        _status = '';
      });
    } catch (e) {
      setState(() {
        _text = '';
        _status = l10n.couldNotReadText(e.toString());
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePdf() async {
    if (_text.trim().isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    try {
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => [
          pw.Header(level: 0, text: l10n.extractedText),
          pw.SizedBox(height: 8),
          pw.Paragraph(text: _text),
        ],
      ));
      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/extracted_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(await doc.save());
      if (mounted) {
        await showResultSheet(context,
            paths: [outPath], title: l10n.extractedText, subtitle: l10n.savedAsPdf);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.saveFailed(e.toString()))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.ocrTitle),
        actions: [
          if (_text.trim().isNotEmpty && !_busy) ...[
            IconButton(
              tooltip: l10n.copy,
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _text));
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(l10n.copied)));
                }
              },
            ),
            IconButton(
              tooltip: l10n.saveAsPdf,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: _savePdf,
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_busy) LinearProgressIndicator(minHeight: 3, backgroundColor: cs.surfaceContainerHighest),
          Material(
            color: cs.surfaceContainerHighest,
            child: InkWell(
              onTap: _busy ? null : _pick,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(children: [
                  Icon(Icons.document_scanner_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _fileName ?? l10n.chooseFileForOcr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Text(_status.isNotEmpty ? _status : (_fileName == null ? '' : l10n.change),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
          Expanded(
            child: _text.trim().isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.text_snippet_outlined, size: 64, color: cs.primary),
                        const SizedBox(height: 16),
                        Text(l10n.extractTextHeadline,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                        const SizedBox(height: 6),
                        Text(l10n.worksOfflineOnDevice,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _busy ? null : _pick,
                          icon: const Icon(Icons.folder_open),
                          label: Text(l10n.chooseFile),
                        ),
                      ]),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(_text, style: const TextStyle(fontSize: 14, height: 1.4)),
                  ),
          ),
        ],
      ),
    );
  }
}
