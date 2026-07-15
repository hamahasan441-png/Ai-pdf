import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../services/offline_pdf_service.dart';

enum PdfToolMode { merge, split }

/// Merge / Split PDFs - all fully offline.
class PdfToolsScreen extends StatefulWidget {
  final PdfToolMode mode;
  const PdfToolsScreen({super.key, required this.mode});
  @override
  State<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends State<PdfToolsScreen> {
  final List<String> _files = [];
  bool _busy = false;
  List<String> _outputs = [];

  String get _title => switch (widget.mode) {
        PdfToolMode.merge => 'Merge PDFs',
        PdfToolMode.split => 'Split PDF',
      };

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      allowMultiple: widget.mode == PdfToolMode.merge,
    );
    if (result != null) {
      setState(() {
        if (widget.mode == PdfToolMode.merge) {
          _files.addAll(result.paths.whereType<String>());
        } else {
          _files
            ..clear()
            ..add(result.files.first.path!);
        }
        _outputs = [];
      });
    }
  }

  Future<void> _run() async {
    if (_files.isEmpty) return;
    setState(() => _busy = true);
    try {
      final svc = OfflinePdfService.instance;
      switch (widget.mode) {
        case PdfToolMode.merge:
          final out = await svc.mergePdfs(_files);
          setState(() => _outputs = [out]);
        case PdfToolMode.split:
          final outs = await svc.splitPdf(_files.first);
          setState(() => _outputs = outs);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Done!')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareAll() async {
    if (_outputs.isNotEmpty) {
      await Share.shareXFiles(_outputs.map((p) => XFile(p)).toList());
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (_outputs.isNotEmpty)
            IconButton(icon: const Icon(Icons.share), onPressed: _shareAll),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // File list
            Expanded(
              child: _files.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.picture_as_pdf_outlined, size: 64, color: cs.outline),
                        const SizedBox(height: 12),
                        Text(widget.mode == PdfToolMode.merge ? 'Choose PDFs to merge' : 'Choose a PDF',
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                    )
                  : ListView(
                      children: [
                        ..._files.asMap().entries.map((e) => Card(
                              child: ListTile(
                                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                                title: Text(e.value.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(() => _files.removeAt(e.key)),
                                ),
                              ),
                            )),
                        if (_outputs.isNotEmpty) ...[
                          const Divider(height: 32),
                          Text('Results (${_outputs.length})', style: const TextStyle(fontWeight: FontWeight.w700)),
                          ..._outputs.map((o) => Card(
                                color: cs.primaryContainer.withOpacity(0.3),
                                child: ListTile(
                                  leading: const Icon(Icons.check_circle, color: Color(0xFF10B981)),
                                  title: Text(o.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                              )),
                        ],
                      ],
                    ),
            ),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.folder_open),
                  label: Text(widget.mode == PdfToolMode.merge ? 'Add PDFs' : 'Choose PDF'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_files.isEmpty || _busy) ? null : _run,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow),
                  label: Text(_busy ? 'Working...' : 'Run'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
