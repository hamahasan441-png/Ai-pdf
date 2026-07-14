import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';

class DocumentUploadScreen extends ConsumerStatefulWidget {
  const DocumentUploadScreen({super.key});

  @override
  ConsumerState<DocumentUploadScreen> createState() =>
      _DocumentUploadScreenState();
}

class _DocumentUploadScreenState extends ConsumerState<DocumentUploadScreen> {
  PlatformFile? _selectedFile;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _error;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: AppConfig.supportedFileExtensions,
      withData: true,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;
      final sizeMB = file.size / (1024 * 1024);

      if (sizeMB > AppConfig.maxUploadSizeMB) {
        setState(() {
          _error = 'File is too large. Maximum size is ${AppConfig.maxUploadSizeMB}MB.';
          _selectedFile = null;
        });
        return;
      }

      setState(() {
        _selectedFile = file;
        _error = null;
      });
    }
  }

  Future<void> _uploadFile() async {
    if (_selectedFile == null) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _error = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          _selectedFile!.bytes!,
          filename: _selectedFile!.name,
        ),
      });

      final response = await apiClient.dio.post(
        AppConstants.uploadEndpoint,
        data: formData,
        onSendProgress: (sent, total) {
          setState(() {
            _uploadProgress = sent / total;
          });
        },
      );

      if (response.statusCode == 201 && mounted) {
        final documentId = response.data['id'];
        context.go('/document/$documentId');
      }
    } on DioException catch (e) {
      setState(() {
        _error = e.response?.data?['detail'] ?? 'Upload failed. Please try again.';
      });
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Upload Document')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drop zone
                InkWell(
                  onTap: _isUploading ? null : _pickFile,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(40),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: colorScheme.outline.withOpacity(0.5),
                        width: 2,
                        strokeAlign: BorderSide.strokeAlignInside,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _selectedFile != null
                              ? Icons.check_circle_outlined
                              : Icons.cloud_upload_outlined,
                          size: 56,
                          color: _selectedFile != null
                              ? colorScheme.primary
                              : colorScheme.outline,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedFile != null
                              ? _selectedFile!.name
                              : 'Tap to select a file',
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Supports PDF, DOCX, PNG, JPG (max ${AppConfig.maxUploadSizeMB}MB)',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: TextStyle(color: colorScheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (_isUploading) ...[
                  const SizedBox(height: 24),
                  LinearProgressIndicator(value: _uploadProgress),
                  const SizedBox(height: 8),
                  Text(
                    '${(_uploadProgress * 100).toInt()}%',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed:
                      (_selectedFile != null && !_isUploading) ? _uploadFile : null,
                  icon: const Icon(Icons.upload),
                  label: const Text('Upload & Analyze'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
