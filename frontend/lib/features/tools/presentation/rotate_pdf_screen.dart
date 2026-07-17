import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/offline_pdf_service.dart';
import '../widgets/result_sheet.dart';

/// Rotate PDF — turns every page by 90, 180, or 270 degrees. Fully offline.
class RotatePdfScreen extends StatefulWidget {
  const RotatePdfScreen({super.key});
  @override
  State<RotatePdfScreen> createState() => _RotatePdfScreenState();
}

class _RotatePdfScreenState extends State<RotatePdfScreen> {
  String? _path;
  bool _busy = false;
  int _degrees = 90;

  Future<void> _pick() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    setState(() => _path = path);
  }

  Future<void> _apply() async {
    if (_path == null) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final out =
          await OfflinePdfService.instance.rotatePdf(_path!, degrees: _degrees);
      if (mounted) {
        await showResultSheet(context,
            paths: [out],
            title: l10n.rotatedDegrees(_degrees),
            subtitle: l10n.everyPageRotated);
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
      appBar: AppBar(title: Text(l10n.toolRotate)),
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
                ]),
              ),
            ),
            const SizedBox(height: 28),
            Text(l10n.rotation, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 90, label: Text('90\u00B0')),
                ButtonSegment(value: 180, label: Text('180\u00B0')),
                ButtonSegment(value: 270, label: Text('270\u00B0')),
              ],
              selected: {_degrees},
              onSelectionChanged:
                  _busy ? null : (s) => setState(() => _degrees = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _degrees == 90
                  ? l10n.rotateCw90
                  : _degrees == 180
                      ? l10n.rotate180
                      : l10n.rotateCcw270,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
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
                  : const Icon(Icons.rotate_right),
              label: Text(_busy ? l10n.rotating : l10n.rotateAllPages),
            ),
          ],
        ),
      ),
    );
  }
}
