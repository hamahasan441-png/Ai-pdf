import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../core/config/app_settings.dart';
import '../../../core/network/openrouter_service.dart';

/// On-device AI: understand any PDF or image directly through OpenRouter,
/// using the user's own key. No backend server required.
///
/// PDFs are rendered to page images (capped resolution, a few pages) and sent
/// with the question to a vision-capable model. Images are sent as-is.
class AskAiScreen extends StatefulWidget {
  const AskAiScreen({super.key});

  @override
  State<AskAiScreen> createState() => _AskAiScreenState();
}

class _AskAiScreenState extends State<AskAiScreen> {
  static const int _maxPages = 3;
  static const double _renderMaxEdge = 1300;

  final _service = OpenRouterService();
  final _questionCtrl = TextEditingController(
    text: 'Read this document and explain what it is, its key details, and anything I should notice.',
  );

  String? _fileName;
  bool _isPdf = false;
  List<String> _imageUrls = []; // data URLs
  bool _busy = false;
  String? _answer;
  String? _error;

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    setState(() {
      _busy = true;
      _answer = null;
      _error = null;
      _fileName = result.files.first.name;
      _imageUrls = [];
    });

    try {
      final lower = path.toLowerCase();
      if (lower.endsWith('.pdf')) {
        _isPdf = true;
        _imageUrls = await _renderPdf(path);
      } else {
        _isPdf = false;
        final bytes = await File(path).readAsBytes();
        final mime = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
        _imageUrls = [OpenRouterService.dataUrl(bytes, mime: mime)];
      }
    } catch (e) {
      _error = 'Could not read file: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<String>> _renderPdf(String path) async {
    final urls = <String>[];
    final doc = await pdfx.PdfDocument.openFile(path);
    try {
      final count = doc.pagesCount < _maxPages ? doc.pagesCount : _maxPages;
      for (var i = 1; i <= count; i++) {
        final page = await doc.getPage(i);
        try {
          final longEdge = page.width > page.height ? page.width : page.height;
          final scale = longEdge > _renderMaxEdge ? _renderMaxEdge / longEdge : 1.0;
          final img = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: pdfx.PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          final bytes = img?.bytes;
          if (bytes != null) {
            urls.add(OpenRouterService.dataUrl(Uint8List.fromList(bytes)));
          }
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    return urls;
  }

  Future<void> _ask() async {
    if (_imageUrls.isEmpty) {
      setState(() => _error = 'Choose a PDF or image first.');
      return;
    }
    setState(() {
      _busy = true;
      _answer = null;
      _error = null;
    });
    try {
      final answer = await _service.ask(
        prompt: _questionCtrl.text.trim().isEmpty
            ? 'Explain this document.'
            : _questionCtrl.text.trim(),
        imageUrls: _imageUrls,
        systemPrompt:
            'You are a precise document assistant. Answer clearly and concisely based only on the provided pages.',
      );
      setState(() => _answer = answer);
    } on OpenRouterException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Understand with AI'),
        actions: [
          FutureBuilder<bool>(
            future: AppSettings.instance.hasOpenRouterKey(),
            builder: (_, snap) {
              final ok = snap.data == true;
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(ok ? 'AI ready' : 'No key'),
                  backgroundColor: ok
                      ? Colors.green.withOpacity(0.15)
                      : cs.errorContainer.withOpacity(0.4),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // File chooser
          InkWell(
            onTap: _busy ? null : _pick,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                border: Border.all(color: _fileName != null ? cs.primary : cs.outlineVariant, width: 2),
                borderRadius: BorderRadius.circular(14),
                color: _fileName != null ? cs.primaryContainer.withOpacity(0.12) : null,
              ),
              child: Row(children: [
                Icon(_fileName == null
                    ? Icons.upload_file
                    : (_isPdf ? Icons.picture_as_pdf : Icons.image),
                    size: 32, color: cs.primary),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _fileName ?? 'Choose a PDF or image',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_fileName != null)
                  const Icon(Icons.check_circle, color: Colors.green),
              ]),
            ),
          ),
          if (_isPdf && _imageUrls.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Reading first ${_imageUrls.length} page(s)',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          const SizedBox(height: 16),

          // Question
          TextField(
            controller: _questionCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Ask anything about it',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: _busy ? null : _ask,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome),
              label: Text(_busy ? 'Thinking...' : 'Ask AI'),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.errorContainer.withOpacity(0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.error_outline, color: cs.error),
                const SizedBox(width: 10),
                Expanded(child: Text(_error!, style: TextStyle(color: cs.onErrorContainer))),
              ]),
            ),
          ],

          if (_answer != null) ...[
            const SizedBox(height: 20),
            Row(children: [
              Icon(Icons.smart_toy_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('AI Answer', style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary)),
              const Spacer(),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: _answer ?? ''));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied')));
                  }
                },
              ),
            ]),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: SelectableText(_answer!, style: const TextStyle(fontSize: 14, height: 1.4)),
            ),
          ],
        ],
      ),
    );
  }
}
