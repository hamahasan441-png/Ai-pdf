import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';

class DocumentDetailScreen extends ConsumerStatefulWidget {
  final String documentId;

  const DocumentDetailScreen({super.key, required this.documentId});

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  Map<String, dynamic>? _document;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get(
        '${AppConstants.documentsEndpoint}/${widget.documentId}',
      );
      setState(() {
        _document = response.data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load document';
        _isLoading = false;
      });
    }
  }


  Future<void> _triggerAnalysis() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.dio.post(
        '${AppConstants.documentsEndpoint}/${widget.documentId}/analyze',
      );
      _loadDocument(); // Reload to get updated status
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to start analysis')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Document')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null || _document == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Document')),
        body: Center(child: Text(_error ?? 'Document not found')),
      );
    }

    final doc = _document!;
    final status = doc['status'] as String;

    return Scaffold(
      appBar: AppBar(
        title: Text(doc['original_filename'] ?? 'Document'),
        actions: [
          if (status == AppConstants.statusFormDetected ||
              status == AppConstants.statusFilled)
            IconButton(
              icon: const Icon(Icons.edit_document),
              onPressed: () => context.push(
                '/document/${widget.documentId}/form',
              ),
              tooltip: 'Review Form Fields',
            ),
          IconButton(
            icon: const Icon(Icons.draw),
            onPressed: () => context.push(
              '/document/${widget.documentId}/editor',
            ),
            tooltip: 'Edit PDF',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status card
            Card(
              child: ListTile(
                leading: _statusIcon(status, colorScheme),
                title: Text('Status: $status'),
                subtitle: Text('Size: ${_formatSize(doc['file_size'])}'),
              ),
            ),
            const SizedBox(height: 16),
            if (doc['ai_summary'] != null) ...[
              Text('AI Summary',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(doc['ai_summary']),
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (status == AppConstants.statusUploaded)
              FilledButton.icon(
                onPressed: _triggerAnalysis,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Analyze with AI'),
              ),
            const SizedBox(height: 12),
            // Pro Edit Button
            OutlinedButton.icon(
              onPressed: () => context.push('/document/${widget.documentId}/editor'),
              icon: const Icon(Icons.draw),
              label: const Text('Edit PDF (Pro Editor)'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusIcon(String status, ColorScheme cs) {
    switch (status) {
      case AppConstants.statusProcessing:
        return CircularProgressIndicator(
            strokeWidth: 2, color: cs.primary);
      case AppConstants.statusAnalyzed:
      case AppConstants.statusFilled:
        return Icon(Icons.check_circle, color: cs.primary);
      case AppConstants.statusError:
        return Icon(Icons.error, color: cs.error);
      default:
        return Icon(Icons.description, color: cs.outline);
    }
  }

  String _formatSize(int? bytes) {
    if (bytes == null) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
