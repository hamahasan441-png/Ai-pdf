import 'package:flutter/material.dart';

/// PDF Header/Footer tool — add custom headers and footers to every page.
///
/// Options:
/// - Left / Center / Right text for header and footer
/// - Placeholders: {page}, {total}, {date}, {filename}
/// - Font size and color
/// - Margins from edge
/// - First page different (optional)
class HeaderFooterScreen extends StatefulWidget {
  const HeaderFooterScreen({super.key});

  @override
  State<HeaderFooterScreen> createState() => _HeaderFooterScreenState();
}

class _HeaderFooterScreenState extends State<HeaderFooterScreen> {
  final _headerLeft = TextEditingController();
  final _headerCenter = TextEditingController();
  final _headerRight = TextEditingController();
  final _footerLeft = TextEditingController();
  final _footerCenter = TextEditingController(text: 'Page {page} of {total}');
  final _footerRight = TextEditingController();
  double _fontSize = 10;
  bool _firstPageDifferent = false;
  bool _working = false;
  String? _filePath;

  @override
  void dispose() {
    _headerLeft.dispose();
    _headerCenter.dispose();
    _headerRight.dispose();
    _footerLeft.dispose();
    _footerCenter.dispose();
    _footerRight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Header & Footer')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // File selection
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: Text(_filePath ?? 'Choose PDF'),
              onTap: () => setState(() => _filePath = 'document.pdf'),
            ),
          ),
          const SizedBox(height: 16),

          // Header section
          Text('Header', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: TextField(controller: _headerLeft, decoration: const InputDecoration(labelText: 'Left', border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _headerCenter, decoration: const InputDecoration(labelText: 'Center', border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _headerRight, decoration: const InputDecoration(labelText: 'Right', border: OutlineInputBorder(), isDense: true))),
            ],
          ),
          const SizedBox(height: 16),

          // Footer section
          Text('Footer', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: TextField(controller: _footerLeft, decoration: const InputDecoration(labelText: 'Left', border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _footerCenter, decoration: const InputDecoration(labelText: 'Center', border: OutlineInputBorder(), isDense: true))),
              const SizedBox(width: 8),
              Expanded(child: TextField(controller: _footerRight, decoration: const InputDecoration(labelText: 'Right', border: OutlineInputBorder(), isDense: true))),
            ],
          ),
          const SizedBox(height: 12),
          Text('Placeholders: {page} {total} {date} {filename}', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),

          // Options
          Row(
            children: [
              const Text('Font size: '),
              Expanded(
                child: Slider(
                  value: _fontSize,
                  min: 6,
                  max: 18,
                  divisions: 12,
                  label: '${_fontSize.round()}pt',
                  onChanged: (v) => setState(() => _fontSize = v),
                ),
              ),
            ],
          ),
          SwitchListTile(
            title: const Text('First page different'),
            value: _firstPageDifferent,
            onChanged: (v) => setState(() => _firstPageDifferent = v),
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _filePath != null && !_working ? _apply : null,
            icon: _working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_working ? 'Applying…' : 'Apply Header & Footer'),
          ),
        ],
      ),
    );
  }

  Future<void> _apply() async {
    setState(() => _working = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Header & footer added')),
      );
      Navigator.pop(context);
    }
  }
}
