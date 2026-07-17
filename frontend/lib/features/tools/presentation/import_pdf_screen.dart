import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../services/pdf_import_service.dart';

/// Screen for importing a PDF from a URL.
///
/// The user pastes any URL (direct PDF link OR a viewer page) and the native
/// engine races 5 legitimate acquisition strategies to retrieve the file as
/// fast as possible. Progress is streamed in real time.
class ImportPdfScreen extends ConsumerStatefulWidget {
  const ImportPdfScreen({super.key});

  @override
  ConsumerState<ImportPdfScreen> createState() => _ImportPdfScreenState();
}

class _ImportPdfScreenState extends ConsumerState<ImportPdfScreen> {
  final _urlController = TextEditingController();
  final _service = PdfImportService.instance;

  bool _isLoading = false;
  double? _progress;
  PdfImportResult? _result;
  StreamSubscription? _progressSub;

  @override
  void dispose() {
    _progressSub?.cancel();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _startImport() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isLoading = true;
      _progress = null;
      _result = null;
    });

    _progressSub?.cancel();
    _progressSub = _service.progressStream.listen((event) {
      if (mounted) {
        setState(() => _progress = event.fraction);
      }
    });

    try {
      final result = await _service.importPdf(url);
      if (mounted) {
        setState(() {
          _isLoading = false;
          _result = result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _result = PdfImportResult(status: 'failed', reason: e.toString());
        });
      }
    } finally {
      _progressSub?.cancel();
    }
  }

  void _cancelImport() {
    _service.cancelImport();
    _progressSub?.cancel();
    setState(() {
      _isLoading = false;
      _progress = null;
    });
  }

  void _shareFile() {
    if (_result?.filePath != null) {
      Share.shareXFiles([XFile(_result!.filePath!)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Import PDF from URL')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.cloud_download,
                        color: Color(0xFF2563EB), size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Fast PDF Import',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          'Paste any PDF URL or viewer page link',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // URL input
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'PDF URL',
                hintText: 'https://example.com/document.pdf',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.link),
                suffixIcon: _urlController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _urlController.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _startImport(),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),

            // Action buttons
            if (!_isLoading)
              FilledButton.icon(
                onPressed:
                    _urlController.text.trim().isEmpty ? null : _startImport,
                icon: const Icon(Icons.download),
                label: const Text('Import PDF'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              )
            else
              Column(
                children: [
                  if (_progress != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: _progress,
                        minHeight: 8,
                        backgroundColor: cs.surfaceContainerHighest,
                      ),
                    )
                  else
                    const LinearProgressIndicator(minHeight: 8),
                  const SizedBox(height: 12),
                  Text(
                    _progress != null
                        ? '${(_progress! * 100).toStringAsFixed(0)}% downloaded'
                        : 'Importing...',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _cancelImport,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            const SizedBox(height: 24),

            // Result
            if (_result != null) _buildResult(cs),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(ColorScheme cs) {
    final r = _result!;
    if (r.isSuccess) {
      final sizeKb = (r.bytes ?? 0) / 1024;
      final sizeMb = sizeKb / 1024;
      final sizeStr = sizeMb >= 1
          ? '${sizeMb.toStringAsFixed(1)} MB'
          : '${sizeKb.toStringAsFixed(0)} KB';
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('PDF Imported Successfully',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _InfoRow(label: 'Pages', value: '${r.pageCount}'),
            _InfoRow(label: 'Size', value: sizeStr),
            _InfoRow(label: 'Strategy', value: r.strategy ?? 'unknown'),
            _InfoRow(label: 'Time', value: '${r.elapsedMs} ms'),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _shareFile,
                    icon: const Icon(Icons.share, size: 18),
                    label: const Text('Share'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // Open in pdfx viewer or another tool
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content: Text('Saved: ${r.filePath}')),
                      );
                    },
                    icon: const Icon(Icons.folder_open, size: 18),
                    label: const Text('Open'),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      final reason = r.reason ?? 'unknown error';
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cs.errorContainer.withOpacity(0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(r.isUnavailable ? Icons.info : Icons.error,
                    color: cs.error, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r.isUnavailable ? 'PDF Not Available' : 'Import Failed',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cs.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(reason,
                style: TextStyle(fontSize: 13, color: cs.onErrorContainer)),
          ],
        ),
      );
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }
}
