import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../../../core/services/tool_handoff.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:share_plus/share_plus.dart';
import '../services/offline_pdf_service.dart';
import '../widgets/result_sheet.dart';

/// PDF to Text — OCR every page and output a .txt file. Fully offline.
class PdfToTextScreen extends StatefulWidget {
  const PdfToTextScreen({super.key});
  @override
  State<PdfToTextScreen> createState() => _PdfToTextScreenState();
}

class _PdfToTextScreenState extends State<PdfToTextScreen> {
  String? _path;
  bool _busy = false;
  String? _outputPath;
  String? _preview;

  @override
  void initState() {
    super.initState();
    final handoff = ToolHandoff.instance.take();
    if (handoff != null) {
      _path = handoff;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _extract();
      });
    }
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    setState(() {
      _path = path;
      _outputPath = null;
      _preview = null;
    });
  }

  Future<void> _extract() async {
    if (_path == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final out = await OfflinePdfService.instance.pdfToText(_path!);
      final text = await File(out).readAsString();
      setState(() {
        _outputPath = out;
        _preview = text.length > 2000 ? '${text.substring(0, 2000)}…' : text;
      });
      if (mounted) {
        await showResultSheet(context,
            paths: [out], title: l10n.textExtracted, subtitle: l10n.txtFileReady);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.operationFailed(e.toString()))));
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
      appBar: AppBar(title: Text(l10n.toolPdfToText)),
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
                      color: _path != null ? cs.primary : cs.outlineVariant,
                      width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(children: [
                  Icon(_path == null ? Icons.upload_file : Icons.picture_as_pdf,
                      size: 48, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    _path == null ? l10n.tapToChoosePdf : _path!.split('/').last,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(l10n.ocrExtractsAllText,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ]),
              ),
            ),
            if (_preview != null) ...[
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _preview!));
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.copiedToClipboard)));
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: Text(l10n.copy),
                ),
                if (_outputPath != null)
                  TextButton.icon(
                    onPressed: () => Share.shareXFiles([XFile(_outputPath!)]),
                    icon: const Icon(Icons.share, size: 16),
                    label: Text(l10n.share),
                  ),
              ]),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(_preview!,
                        style: const TextStyle(fontSize: 13, height: 1.4)),
                  ),
                ),
              ),
            ] else
              const Spacer(),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: (_path == null || _busy) ? null : _extract,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.text_snippet_outlined),
              label: Text(_busy ? l10n.extractingText : l10n.toolExtractText),
            ),
          ],
        ),
      ),
    );
  }
}
