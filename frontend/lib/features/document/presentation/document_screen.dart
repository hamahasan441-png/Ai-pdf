import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';

class DocumentScreen extends ConsumerStatefulWidget {
  final String id;
  const DocumentScreen({super.key, required this.id});
  @override
  ConsumerState<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends ConsumerState<DocumentScreen> {
  Map<String, dynamic>? _doc;
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final hasAuth = await api.hasToken();
      final endpoint = hasAuth
          ? '${AppConstants.documentsEndpoint}/${widget.id}'
          : '/documents/guest/${widget.id}';
      final r = await api.dio.get(endpoint);
      setState(() { _doc = r.data; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _process() async {
    setState(() => _processing = true);
    try {
      final api = ref.read(apiClientProvider);
      final hasAuth = await api.hasToken();
      final endpoint = hasAuth
          ? '${AppConstants.documentsEndpoint}/${widget.id}/analyze'
          : '/documents/guest/${widget.id}/analyze';
      await api.dio.post(endpoint);
      await _load();
    } catch (_) {}
    setState(() => _processing = false);
  }

  Future<void> _export(String format) async {
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('${AppConstants.documentsEndpoint}/${widget.id}/export', data: {'format': format});
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported as $format')));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export failed')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    if (_doc == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Document not found')));
    final cs = Theme.of(context).colorScheme;
    final status = _doc!['status'] ?? 'uploaded';
    final fields = (_doc!['form_fields'] as List?) ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(_doc!['original_filename'] ?? 'Document', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(icon: const Icon(Icons.edit_note), tooltip: 'Pro Editor', onPressed: () => context.push('/editor/${widget.id}')),
          PopupMenuButton<String>(
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'pdf', child: Text('Export PDF')),
              const PopupMenuItem(value: 'docx', child: Text('Export DOCX')),
            ],
            onSelected: _export,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          // Info card
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _row('Status', status.toUpperCase(), status == 'filled' ? Colors.green : cs.primary),
            _row('Pages', '${_doc!['page_count'] ?? 1}', null),
            _row('Language', _doc!['language'] ?? 'en', null),
            if (_doc!['needs_ocr'] == true) _row('OCR', 'Required', Colors.orange),
          ]))),
          const SizedBox(height: 16),
          // Actions
          if (status == 'uploaded') ...[
            SizedBox(height: 50, child: FilledButton.icon(
              onPressed: _processing ? null : _process,
              icon: _processing ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.auto_awesome),
              label: Text(_processing ? 'Analyzing...' : 'Analyze with AI'),
            )),
            const SizedBox(height: 12),
          ],
          SizedBox(height: 50, child: OutlinedButton.icon(
            onPressed: () => context.push('/editor/${widget.id}'),
            icon: const Icon(Icons.draw),
            label: const Text('Open Pro Editor'),
          )),
          const SizedBox(height: 20),
          // Fields
          if (fields.isNotEmpty) ...[
            Text('Detected Fields (${fields.length})', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...fields.map((f) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                dense: true,
                leading: Icon(f['confirmed_value'] != null ? Icons.check_circle : Icons.radio_button_unchecked, color: f['confirmed_value'] != null ? Colors.green : Colors.grey, size: 20),
                title: Text(f['field_label'] ?? f['field_name'] ?? 'Field', style: const TextStyle(fontSize: 14)),
                subtitle: Text(f['confirmed_value'] ?? f['suggested_value'] ?? 'Empty', style: const TextStyle(fontSize: 12)),
              ),
            )),
          ],
        ]),
      ),
    );
  }

  Widget _row(String label, String value, Color? valueColor) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      Text(value, style: TextStyle(fontWeight: FontWeight.w600, color: valueColor)),
    ]),
  );
}
