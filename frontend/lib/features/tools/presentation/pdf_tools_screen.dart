import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../services/offline_pdf_service.dart';
import '../widgets/result_sheet.dart';

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
    final l10n = AppLocalizations.of(context)!;
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
      if (mounted && _outputs.isNotEmpty) {
        await showResultSheet(context,
            paths: _outputs,
            title: widget.mode == PdfToolMode.merge ? l10n.mergedTitle : l10n.splitComplete,
            subtitle: widget.mode == PdfToolMode.merge
                ? l10n.pdfsCombined(_files.length)
                : l10n.pagesCreated(_outputs.length));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.operationFailed(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareAll() async {
    final l10n = AppLocalizations.of(context)!;
    if (_outputs.isNotEmpty) {
      await showResultSheet(context, paths: _outputs, title: l10n.yourFiles);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isMerge = widget.mode == PdfToolMode.merge;
    final title = isMerge ? l10n.mergePdfsTitle : l10n.toolSplit;
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
                        Text(isMerge ? l10n.choosePdfsToMerge : l10n.chooseAPdf,
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
                          Text(l10n.resultsCount(_outputs.length), style: const TextStyle(fontWeight: FontWeight.w700)),
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
                  label: Text(isMerge ? l10n.addPdfs : l10n.choosePdf),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: (_files.isEmpty || _busy) ? null : _run,
                  icon: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.play_arrow),
                  label: Text(_busy ? l10n.working : l10n.run),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
