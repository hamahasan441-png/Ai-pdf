import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_theme.dart';
import '../services/pdf_import_service.dart';

/// Import any file from a URL.
///
/// The user pastes any URL (direct file link OR a PDF viewer page). The native
/// engine downloads it as fast as possible (parallel range download), detects
/// what it is, shows the details/preview, and lets the user save it anywhere via
/// the system "Save as" dialog. All acquisition uses legitimate browser behavior.
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
  ImportedFile? _result;
  StreamSubscription? _progressSub;
  bool _saving = false;

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
      if (mounted) setState(() => _progress = event.fraction);
    });

    try {
      final result = await _service.importFile(url);
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
          _result = ImportedFile(status: 'failed', reason: e.toString());
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

  Future<void> _saveToDevice() async {
    final r = _result;
    if (r?.filePath == null) return;
    setState(() => _saving = true);
    try {
      final res = await _service.saveFile(
        sourcePath: r!.filePath!,
        fileName: r.fileName ?? 'download',
        mimeType: r.mimeType ?? 'application/octet-stream',
      );
      if (!mounted) return;
      final msg = res.saved
          ? 'Saved successfully'
          : (res.reason != null ? 'Not saved: ${res.reason}' : 'Save cancelled');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
      appBar: AppBar(title: const Text('Import File from URL')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(cs),
            const SizedBox(height: 24),
            TextField(
              controller: _urlController,
              decoration: InputDecoration(
                labelText: 'File URL',
                hintText: 'https://example.com/document.pdf',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
            if (!_isLoading)
              FilledButton.icon(
                onPressed:
                    _urlController.text.trim().isEmpty ? null : _startImport,
                icon: const Icon(Icons.download),
                label: const Text('Grab File'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              )
            else
              _loadingBlock(cs),
            const SizedBox(height: 24),
            if (_result != null) _buildResult(cs),
          ],
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) => Container(
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
                  const Text('Fast File Import',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('Grab any file from a URL, then save it to your device',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _loadingBlock(ColorScheme cs) => Column(
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
                : 'Downloading...',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
              onPressed: _cancelImport, child: const Text('Cancel')),
        ],
      );

  Widget _buildResult(ColorScheme cs) {
    final r = _result!;
    if (!r.isSuccess) {
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
            Row(children: [
              Icon(r.isUnavailable ? Icons.info : Icons.error,
                  color: cs.error, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    r.isUnavailable ? 'File Not Available' : 'Download Failed',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: cs.error)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(reason,
                style: TextStyle(fontSize: 13, color: cs.onErrorContainer)),
          ],
        ),
      );
    }

    // Success: show what was downloaded.
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
          Row(children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 22),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Downloaded',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
          const SizedBox(height: 14),

          // Preview: image thumbnail if it's an image, else a type icon.
          if (r.isImage && r.filePath != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(r.filePath!),
                height: 160,
                width: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => _typeIconRow(cs),
              ),
            )
          else
            _typeIconRow(cs),
          const SizedBox(height: 14),

          _InfoRow(label: 'Name', value: r.fileName ?? '—'),
          _InfoRow(label: 'Type', value: r.mimeType ?? '—'),
          _InfoRow(label: 'Size', value: r.readableSize),
          if (r.pageCount != null)
            _InfoRow(label: 'Pages', value: '${r.pageCount}'),
          if (r.elapsedMs != null)
            _InfoRow(label: 'Time', value: '${r.elapsedMs} ms'),
          const SizedBox(height: 14),

          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _saving ? null : _saveToDevice,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_alt, size: 18),
                label: Text(_saving ? 'Saving...' : 'Save to device'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _shareFile,
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Share'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _typeIconRow(ColorScheme cs) {
    final r = _result!;
    return Row(children: [
      Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: cs.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(_iconForMime(r.mimeType), color: cs.primary, size: 30),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Text(
          r.fileName ?? 'file',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
    ]);
  }

  IconData _iconForMime(String? mime) {
    final m = mime ?? '';
    if (m == 'application/pdf') return Icons.picture_as_pdf;
    if (m.startsWith('image/')) return Icons.image;
    if (m.startsWith('video/')) return Icons.movie;
    if (m.startsWith('audio/')) return Icons.audiotrack;
    if (m.startsWith('text/')) return Icons.description;
    if (m.contains('zip') || m.contains('rar') || m.contains('gzip')) {
      return Icons.folder_zip;
    }
    if (m.contains('word') || m.contains('document')) return Icons.article;
    if (m.contains('sheet') || m.contains('excel')) return Icons.table_chart;
    if (m.contains('presentation') || m.contains('powerpoint')) {
      return Icons.slideshow;
    }
    return Icons.insert_drive_file;
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 68,
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
