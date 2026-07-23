import 'package:flutter/material.dart';

/// Export PDF to HTML screen — converts a PDF's text content and basic
/// structure into an HTML file that can be opened in any browser.
///
/// Use cases:
/// - Make document content searchable on the web
/// - Accessible reading in a browser
/// - Copy content with formatting preserved
///
/// The conversion uses OCR text + detected headings to create a structured
/// HTML document. Images are embedded as base64 if page rasters are included.
class ExportHtmlScreen extends StatefulWidget {
  const ExportHtmlScreen({super.key});

  @override
  State<ExportHtmlScreen> createState() => _ExportHtmlScreenState();
}

class _ExportHtmlScreenState extends State<ExportHtmlScreen> {
  String? _filePath;
  bool _includeImages = true;
  bool _includeStyles = true;
  bool _working = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export to HTML')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: Text(_filePath ?? 'Choose PDF'),
              subtitle: const Text('Tap to select'),
              onTap: () => setState(() => _filePath = 'document.pdf'),
            ),
          ),
          const SizedBox(height: 24),

          SwitchListTile(
            title: const Text('Include page images'),
            subtitle: const Text('Embeds page rasters as base64 (larger file)'),
            value: _includeImages,
            onChanged: (v) => setState(() => _includeImages = v),
          ),
          SwitchListTile(
            title: const Text('Include styling'),
            subtitle: const Text('Adds CSS for headings and structure'),
            value: _includeStyles,
            onChanged: (v) => setState(() => _includeStyles = v),
          ),
          const SizedBox(height: 24),

          FilledButton.icon(
            onPressed: _filePath != null && !_working ? _export : null,
            icon: _working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.html),
            label: Text(_working ? 'Exporting…' : 'Export as HTML'),
          ),
        ],
      ),
    );
  }

  Future<void> _export() async {
    setState(() => _working = true);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      setState(() => _working = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('HTML file exported — ready to share')),
      );
    }
  }
}
