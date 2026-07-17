import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/offline_pdf_service.dart';
import '../widgets/result_sheet.dart';

/// Small shared helper: a tappable "choose a PDF" drop zone.
class _PdfPicker extends StatelessWidget {
  final String? fileName;
  final bool busy;
  final VoidCallback onTap;
  const _PdfPicker({required this.fileName, required this.busy, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          border: Border.all(
              color: fileName != null ? cs.primary : cs.outlineVariant, width: 2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(children: [
          Icon(fileName == null ? Icons.upload_file : Icons.picture_as_pdf,
              size: 48, color: cs.primary),
          const SizedBox(height: 12),
          Text(
            fileName ?? AppLocalizations.of(context)!.tapToChoosePdf,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ]),
      ),
    );
  }
}

Future<String?> _pickPdf() async {
  final result = await FilePicker.platform
      .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
  if (result == null || result.files.isEmpty) return null;
  return result.files.first.path;
}

// ============================================================
// WATERMARK
// ============================================================

class WatermarkScreen extends StatefulWidget {
  const WatermarkScreen({super.key});
  @override
  State<WatermarkScreen> createState() => _WatermarkScreenState();
}

class _WatermarkScreenState extends State<WatermarkScreen> {
  String? _path;
  bool _busy = false;
  double _opacity = 0.25;
  final _ctrl = TextEditingController(text: 'CONFIDENTIAL');

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final p = await _pickPdf();
    if (p == null) return;
    setState(() => _path = p);
  }

  Future<void> _apply() async {
    if (_path == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final out = await OfflinePdfService.instance
          .watermarkPdf(_path!, _ctrl.text, opacity: _opacity);
      if (mounted) {
        await showResultSheet(context,
            paths: [out], title: l10n.watermarkAdded, subtitle: l10n.everyPageStamped);
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
      appBar: AppBar(title: Text(l10n.addWatermark)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PdfPicker(
                fileName: _path?.split('/').last, busy: _busy, onTap: _pick),
            const SizedBox(height: 24),
            TextField(
              controller: _ctrl,
              enabled: !_busy,
              decoration: InputDecoration(
                labelText: l10n.watermarkText,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Text(l10n.opacity, style: const TextStyle(fontWeight: FontWeight.w600)),
              Expanded(
                child: Slider(
                  value: _opacity,
                  min: 0.05,
                  max: 0.6,
                  divisions: 11,
                  label: '${(_opacity * 100).round()}%',
                  onChanged: _busy ? null : (v) => setState(() => _opacity = v),
                ),
              ),
              Text('${(_opacity * 100).round()}%',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ]),
            const Spacer(),
            FilledButton.icon(
              onPressed: (_path == null || _busy) ? null : _apply,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.branding_watermark_outlined),
              label: Text(_busy ? l10n.applying : l10n.addWatermark),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PAGE NUMBERS
// ============================================================

class PageNumbersScreen extends StatefulWidget {
  const PageNumbersScreen({super.key});
  @override
  State<PageNumbersScreen> createState() => _PageNumbersScreenState();
}

class _PageNumbersScreenState extends State<PageNumbersScreen> {
  String? _path;
  bool _busy = false;

  Future<void> _pick() async {
    final p = await _pickPdf();
    if (p == null) return;
    setState(() => _path = p);
  }

  Future<void> _apply() async {
    if (_path == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final out = await OfflinePdfService.instance.addPageNumbers(_path!);
      if (mounted) {
        await showResultSheet(context,
            paths: [out], title: l10n.pageNumbersAdded, subtitle: l10n.bottomCenterEveryPage);
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
      appBar: AppBar(title: Text(l10n.addPageNumbers)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PdfPicker(
                fileName: _path?.split('/').last, busy: _busy, onTap: _pick),
            const SizedBox(height: 20),
            Text(
              l10n.pageNumbersHint,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: (_path == null || _busy) ? null : _apply,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.numbers),
              label: Text(_busy ? l10n.applying : l10n.addPageNumbers),
            ),
          ],
        ),
      ),
    );
  }
}
