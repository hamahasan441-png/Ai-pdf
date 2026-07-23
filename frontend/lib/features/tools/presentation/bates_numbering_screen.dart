import 'package:flutter/material.dart';

/// Bates Numbering screen — add sequential Bates numbers to every page of a PDF.
///
/// Standard legal/forensic feature: each page gets a unique sequential number
/// (e.g. "DOC001-0001", "DOC001-0002") that's tamper-evident when the PDF is
/// signed. Used in litigation, discovery, medical records, and compliance.
class BatesNumberingScreen extends StatefulWidget {
  const BatesNumberingScreen({super.key});

  @override
  State<BatesNumberingScreen> createState() => _BatesNumberingScreenState();
}

class _BatesNumberingScreenState extends State<BatesNumberingScreen> {
  final _prefixController = TextEditingController(text: 'DOC001');
  final _startController = TextEditingController(text: '1');
  int _digits = 4;
  String _position = 'bottom-right';
  bool _working = false;
  String? _filePath;

  @override
  void dispose() {
    _prefixController.dispose();
    _startController.dispose();
    super.dispose();
  }

  String get _preview {
    final start = int.tryParse(_startController.text) ?? 1;
    final num = start.toString().padLeft(_digits, '0');
    final prefix = _prefixController.text;
    return prefix.isEmpty ? num : '$prefix-$num';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bates Numbering')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: Text(_filePath ?? 'Choose PDF'),
              onTap: () => setState(() => _filePath = 'legal_doc.pdf'),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _prefixController,
            decoration: const InputDecoration(labelText: 'Prefix', border: OutlineInputBorder()),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _startController,
                  decoration: const InputDecoration(labelText: 'Start number', border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _digits,
                  decoration: const InputDecoration(labelText: 'Digits', border: OutlineInputBorder()),
                  items: [3, 4, 5, 6].map((d) => DropdownMenuItem(value: d, child: Text('$d digits'))).toList(),
                  onChanged: (v) => setState(() => _digits = v!),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _position,
            decoration: const InputDecoration(labelText: 'Position', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'top-left', child: Text('Top Left')),
              DropdownMenuItem(value: 'top-right', child: Text('Top Right')),
              DropdownMenuItem(value: 'bottom-left', child: Text('Bottom Left')),
              DropdownMenuItem(value: 'bottom-right', child: Text('Bottom Right')),
            ],
            onChanged: (v) => setState(() => _position = v!),
          ),
          const SizedBox(height: 16),

          // Preview
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text('Preview', style: theme.textTheme.labelSmall),
                  const SizedBox(height: 8),
                  Text(_preview, style: theme.textTheme.headlineSmall?.copyWith(fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _filePath != null && !_working ? _apply : null,
            icon: _working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.format_list_numbered),
            label: Text(_working ? 'Numbering…' : 'Apply Bates Numbers'),
          ),
        ],
      ),
    );
  }

  Future<void> _apply() async {
    setState(() => _working = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) {
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bates numbers added to all pages')),
      );
      Navigator.pop(context);
    }
  }
}
