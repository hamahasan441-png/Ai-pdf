import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';

class UploadScreen extends ConsumerStatefulWidget {
  const UploadScreen({super.key});
  @override
  ConsumerState<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends ConsumerState<UploadScreen> {
  PlatformFile? _file;
  bool _uploading = false;
  double _progress = 0;
  String? _error;

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConfig.supportedExtensions,
    );
    if (r != null && r.files.isNotEmpty) {
      setState(() { _file = r.files.first; _error = null; });
    }
  }

  Future<void> _upload() async {
    if (_file == null || _file!.path == null) return;
    setState(() { _uploading = true; _progress = 0; _error = null; });
    try {
      final api = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(_file!.path!, filename: _file!.name),
      });
      final r = await api.dio.post(
        AppConstants.uploadEndpoint,
        data: formData,
        options: Options(sendTimeout: AppConfig.uploadTimeout, receiveTimeout: AppConfig.uploadTimeout),
        onSendProgress: (s, t) => setState(() => _progress = s / t),
      );
      if (mounted && r.statusCode == 201) {
        context.go('/document/${r.data['id']}');
      }
    } catch (e) {
      setState(() => _error = 'Upload failed. Please try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Upload Document')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: GestureDetector(
              onTap: _uploading ? null : _pick,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: _file != null ? cs.primary : cs.outlineVariant, width: 2),
                  borderRadius: BorderRadius.circular(16),
                  color: _file != null ? cs.primaryContainer.withOpacity(0.1) : null,
                ),
                child: _file != null ? _filePreview(cs) : _dropZone(cs),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: cs.error), textAlign: TextAlign.center),
          ],
          if (_uploading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 4),
            Text('${(_progress * 100).toInt()}%', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          ],
          const SizedBox(height: 20),
          SizedBox(height: 52, child: FilledButton.icon(
            onPressed: (_file != null && !_uploading) ? _upload : null,
            icon: _uploading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.cloud_upload),
            label: Text(_uploading ? 'Uploading...' : 'Upload & Analyze'),
          )),
        ]),
      ),
    );
  }

  Widget _dropZone(ColorScheme cs) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.cloud_upload_outlined, size: 64, color: cs.primary),
    const SizedBox(height: 16),
    Text('Tap to select a file', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: cs.onSurface)),
    const SizedBox(height: 8),
    Text('PDF, Word, or Image (max ${AppConfig.maxFileSizeMB}MB)', style: TextStyle(color: cs.onSurfaceVariant)),
  ]);

  Widget _filePreview(ColorScheme cs) => Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(Icons.insert_drive_file, size: 48, color: cs.primary),
    const SizedBox(height: 12),
    Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: Text(_file!.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
    const SizedBox(height: 4),
    Text('${(_file!.size / 1024 / 1024).toStringAsFixed(2)} MB', style: TextStyle(color: cs.onSurfaceVariant)),
    const SizedBox(height: 12),
    TextButton.icon(onPressed: _uploading ? null : _pick, icon: const Icon(Icons.swap_horiz, size: 18), label: const Text('Change file')),
  ]);
}
