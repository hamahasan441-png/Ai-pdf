import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/offline_pdf_service.dart';

/// Compress - fully offline. Shrinks images or PDFs on-device.
class CompressScreen extends StatefulWidget {
  const CompressScreen({super.key});
  @override
  State<CompressScreen> createState() => _CompressScreenState();
}

class _CompressScreenState extends State<CompressScreen> {
  String? _filePath;
  bool _isPdf = false;
  bool _busy = false;
  double _quality = 70;
  CompressResult? _result;

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );
    if (result != null && result.files.isNotEmpty) {
      final path = result.files.first.path!;
      setState(() {
        _filePath = path;
        _isPdf = path.toLowerCase().endsWith('.pdf');
        _result = null;
      });
    }
  }

  Future<void> _compress() async {
    if (_filePath == null) return;
    setState(() => _busy = true);
    try {
      final svc = OfflinePdfService.instance;
      final result = _isPdf
          ? await svc.compressPdf(_filePath!)
          : await svc.compressImage(_filePath!, quality: _quality.toInt(), maxWidth: 1920);
      setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Compression failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_result != null) {
      await Share.shareXFiles([XFile(_result!.outputPath)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Compress File')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File picker card
            InkWell(
              onTap: _busy ? null : _pick,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  border: Border.all(color: _filePath != null ? cs.primary : cs.outlineVariant, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(children: [
                  Icon(_filePath == null ? Icons.upload_file : (_isPdf ? Icons.picture_as_pdf : Icons.image),
                      size: 48, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    _filePath == null ? 'Tap to choose a file' : _filePath!.split('/').last,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text('JPG, PNG, or PDF', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                ]),
              ),
            ),
            const SizedBox(height: 24),

            // Quality slider (images only)
            if (_filePath != null && !_isPdf) ...[
              Row(children: [
                const Text('Quality', style: TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${_quality.toInt()}%', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
              ]),
              Slider(value: _quality, min: 10, max: 95, divisions: 17, onChanged: (v) => setState(() => _quality = v)),
              Text('Lower quality = smaller file', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              const SizedBox(height: 16),
            ],

            // Result card
            if (_result != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _stat('Before', _result!.originalSizeLabel, cs.onSurfaceVariant),
                    const Icon(Icons.arrow_forward),
                    _stat('After', _result!.compressedSizeLabel, cs.primary),
                  ]),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(20)),
                    child: Text(
                      '${_result!.reductionPercent.toStringAsFixed(0)}% smaller',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(onPressed: _share, icon: const Icon(Icons.share), label: const Text('Save / Share')),
            ],

            const Spacer(),
            FilledButton.icon(
              onPressed: (_filePath == null || _busy) ? null : _compress,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.compress),
              label: Text(_busy ? 'Compressing...' : 'Compress'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Column(children: [
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
      ]);
}
