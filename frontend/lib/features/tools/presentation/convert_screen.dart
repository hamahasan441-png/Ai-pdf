import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import '../services/conversion_service.dart';
import '../widgets/result_sheet.dart';

/// Convert a PDF to an Office format (Word / Excel / PowerPoint) via the
/// managed backend. Cloud feature — needs a configured server.
class ConvertScreen extends StatefulWidget {
  const ConvertScreen({super.key});
  @override
  State<ConvertScreen> createState() => _ConvertScreenState();
}

class _ConvertScreenState extends State<ConvertScreen> {
  String? _path;
  ConvertFormat _format = ConvertFormat.word;
  bool _busy = false;

  Future<void> _pick() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    setState(() => _path = path);
  }

  Future<void> _convert() async {
    if (_path == null) return;
    final l10n = AppLocalizations.of(context)!;
    if (!ConversionService.instance.serverConfigured) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.convertNeedsServer)));
      return;
    }
    setState(() => _busy = true);
    try {
      final out = await ConversionService.instance.convert(_path!, _format);
      if (mounted) {
        await showResultSheet(context, paths: [out], title: l10n.convertedTitle);
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
      appBar: AppBar(title: Text(l10n.convert)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!ConversionService.instance.serverConfigured)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.error.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.error.withOpacity(0.3)),
                ),
                child: Row(children: [
                  Icon(Icons.cloud_off_outlined, color: cs.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(l10n.convertNeedsServer,
                      style: TextStyle(fontSize: 13, color: cs.error))),
                ]),
              ),
            InkWell(
              onTap: _busy ? null : _pick,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: _path != null ? cs.primary : cs.outlineVariant, width: 2),
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
                ]),
              ),
            ),
            const SizedBox(height: 24),
            _formatTile(cs, ConvertFormat.word, Icons.description, l10n.convertToWord, const Color(0xFF2B579A)),
            const SizedBox(height: 10),
            _formatTile(cs, ConvertFormat.excel, Icons.table_chart, l10n.convertToExcel, const Color(0xFF217346)),
            const SizedBox(height: 10),
            _formatTile(cs, ConvertFormat.ppt, Icons.slideshow, l10n.convertToPpt, const Color(0xFFD24726)),
            const Spacer(),
            FilledButton.icon(
              onPressed: (_path == null || _busy) ? null : _convert,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.sync_alt),
              label: Text(_busy ? l10n.converting : l10n.convert),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatTile(ColorScheme cs, ConvertFormat f, IconData icon, String label, Color color) {
    final selected = _format == f;
    return InkWell(
      onTap: _busy ? null : () => setState(() => _format = f),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.08) : cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? color : cs.outlineVariant, width: selected ? 2 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (selected) Icon(Icons.check_circle, color: color, size: 20),
        ]),
      ),
    );
  }
}
