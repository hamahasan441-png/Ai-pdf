import 'package:flutter/material.dart';

/// Batch processing screen — apply operations to multiple PDFs at once.
///
/// Supported batch operations:
/// - Compress all files
/// - Add watermark to all
/// - Add page numbers to all
/// - Convert all to images
/// - OCR all (extract text)
/// - Rotate all
/// - Password protect all
///
/// Shows real-time progress (file X of Y) with individual success/failure status.
class BatchProcessScreen extends StatefulWidget {
  const BatchProcessScreen({super.key});

  @override
  State<BatchProcessScreen> createState() => _BatchProcessScreenState();
}

enum BatchOperation { compress, watermark, pageNumbers, toImages, ocr, rotate, protect }

class _BatchProcessScreenState extends State<BatchProcessScreen> {
  final List<_BatchFile> _files = [];
  BatchOperation _operation = BatchOperation.compress;
  bool _processing = false;
  int _progress = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Batch Processing')),
      body: Column(
        children: [
          // Operation selector
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<BatchOperation>(
              value: _operation,
              decoration: const InputDecoration(
                labelText: 'Operation',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.settings),
              ),
              items: BatchOperation.values.map((op) {
                final label = switch (op) {
                  BatchOperation.compress => 'Compress',
                  BatchOperation.watermark => 'Add watermark',
                  BatchOperation.pageNumbers => 'Add page numbers',
                  BatchOperation.toImages => 'Convert to images',
                  BatchOperation.ocr => 'Extract text (OCR)',
                  BatchOperation.rotate => 'Rotate all',
                  BatchOperation.protect => 'Password protect',
                };
                return DropdownMenuItem(value: op, child: Text(label));
              }).toList(),
              onChanged: _processing ? null : (v) => setState(() => _operation = v!),
            ),
          ),

          // File list
          Expanded(
            child: _files.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open, size: 48, color: theme.colorScheme.outline),
                        const SizedBox(height: 12),
                        const Text('No files selected'),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _addFiles,
                          icon: const Icon(Icons.add),
                          label: const Text('Add PDFs'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _files.length,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemBuilder: (context, i) {
                      final file = _files[i];
                      return ListTile(
                        leading: Icon(
                          file.status == _Status.success
                              ? Icons.check_circle
                              : file.status == _Status.failed
                                  ? Icons.error
                                  : file.status == _Status.processing
                                      ? Icons.hourglass_top
                                      : Icons.picture_as_pdf,
                          color: file.status == _Status.success
                              ? Colors.green
                              : file.status == _Status.failed
                                  ? theme.colorScheme.error
                                  : null,
                        ),
                        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: !_processing
                            ? IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() => _files.removeAt(i)),
                              )
                            : null,
                      );
                    },
                  ),
          ),

          // Progress + action
          if (_processing)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  LinearProgressIndicator(value: _files.isEmpty ? 0 : _progress / _files.length),
                  const SizedBox(height: 8),
                  Text('Processing ${_progress + 1} of ${_files.length}…'),
                ],
              ),
            ),

          // Bottom bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (!_processing)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _addFiles,
                        icon: const Icon(Icons.add),
                        label: Text('Add (${_files.length})'),
                      ),
                    ),
                  if (!_processing) const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _files.isNotEmpty && !_processing ? _runBatch : null,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Process all'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _addFiles() {
    // In production: file_picker multi-select.
    setState(() {
      _files.addAll([
        _BatchFile('Document_1.pdf'),
        _BatchFile('Document_2.pdf'),
        _BatchFile('Report_final.pdf'),
      ]);
    });
  }

  Future<void> _runBatch() async {
    setState(() {
      _processing = true;
      _progress = 0;
      for (final f in _files) {
        f.status = _Status.pending;
      }
    });

    for (var i = 0; i < _files.length; i++) {
      setState(() {
        _progress = i;
        _files[i].status = _Status.processing;
      });

      // Simulate processing (in production: call the actual service).
      await Future<void>.delayed(const Duration(milliseconds: 800));

      setState(() => _files[i].status = _Status.success);
    }

    setState(() => _processing = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Processed ${_files.length} files')),
      );
    }
  }
}

enum _Status { pending, processing, success, failed }

class _BatchFile {
  final String name;
  _Status status;

  _BatchFile(this.name, {this.status = _Status.pending});
}
