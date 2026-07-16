import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../services/offline_pdf_service.dart';
import '../widgets/result_sheet.dart';

/// Delete Pages — remove a range of pages from a PDF, keep the rest. Offline.
class DeletePagesScreen extends StatefulWidget {
  const DeletePagesScreen({super.key});
  @override
  State<DeletePagesScreen> createState() => _DeletePagesScreenState();
}

class _DeletePagesScreenState extends State<DeletePagesScreen> {
  String? _path;
  int _pageCount = 0;
  bool _busy = false;
  final _fromCtrl = TextEditingController(text: '1');
  final _toCtrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _fromCtrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;
    final count = await OfflinePdfService.instance.getPageCount(path);
    setState(() {
      _path = path;
      _pageCount = count;
      _fromCtrl.text = '1';
      _toCtrl.text = '1';
    });
  }

  Future<void> _delete() async {
    if (_path == null) return;
    final from = int.tryParse(_fromCtrl.text.trim()) ?? 1;
    final to = int.tryParse(_toCtrl.text.trim()) ?? from;
    if (from < 1 || to < from || from > _pageCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid page range')),
      );
      return;
    }
    final removed = to.clamp(from, _pageCount) - from + 1;
    if (removed >= _pageCount) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That would delete every page')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final out =
          await OfflinePdfService.instance.deletePages(_path!, from: from, to: to);
      if (mounted) {
        await showResultSheet(context,
            paths: [out],
            title: 'Deleted pages $from–$to',
            subtitle: '${_pageCount - removed} page${_pageCount - removed == 1 ? '' : 's'} kept');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Delete Pages')),
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
                    _path == null
                        ? 'Tap to choose a PDF'
                        : '${_path!.split('/').last} ($_pageCount pages)',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
            ),
            if (_path != null) ...[
              const SizedBox(height: 28),
              const Text('Pages to remove',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _fromCtrl,
                    keyboardType: TextInputType.number,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'From',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('to', style: TextStyle(fontSize: 16)),
                ),
                Expanded(
                  child: TextField(
                    controller: _toCtrl,
                    keyboardType: TextInputType.number,
                    enabled: !_busy,
                    decoration: const InputDecoration(
                      labelText: 'To',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(
                'Total pages: $_pageCount. The rest are kept in order.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
            const Spacer(),
            FilledButton.icon(
              onPressed: (_path == null || _busy) ? null : _delete,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_sweep_outlined),
              label: Text(_busy ? 'Removing...' : 'Delete Pages'),
            ),
          ],
        ),
      ),
    );
  }
}
