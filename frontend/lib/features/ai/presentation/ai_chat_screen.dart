import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../core/config/app_settings.dart';
import '../../../core/network/openrouter_service.dart';

/// The two AI experiences, both powered by the same on-device chat engine.
enum AiChatMode { understand, fillForm }

/// A smart, multi-turn AI chat that can SEE a document (PDF/image).
///
/// - Understand: ask anything about the document, conversationally.
/// - Fill Form: the AI reads the form, asks you for the info it needs, you
///   chat to provide it, and it produces the completed field values.
///
/// Runs directly on the phone through OpenRouter with the user's own key.
class AiChatScreen extends StatefulWidget {
  final AiChatMode mode;
  const AiChatScreen({super.key, required this.mode});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _ChatMsg {
  final String role; // 'user' | 'assistant'
  String text;
  _ChatMsg(this.role, this.text);
}

class _AiChatScreenState extends State<AiChatScreen> {
  static const int _maxPages = 2;
  static const double _renderMaxEdge = 1200;

  final _service = OpenRouterService();
  final _inputCtrl = TextEditingController();
  final _scroll = ScrollController();

  String? _fileName;
  bool _isPdf = false;
  List<String> _docImages = []; // data URLs attached to the first user turn

  final List<_ChatMsg> _messages = [];
  bool _busy = false;
  bool _loadingDoc = false;
  String? _error;

  bool get _isForm => widget.mode == AiChatMode.fillForm;

  String get _title => _isForm ? 'Fill Form with AI' : 'Understand with AI';

  String get _systemPrompt => _isForm
      ? 'You are an expert form-filling assistant. The user shares a form as page '
          'images. Steps: (1) Read the form carefully and identify every field or '
          'blank that needs a value. (2) Ask the user for the specific information '
          'you need, grouped logically and in plain language. Only ask for what the '
          'form requires. (3) As the user replies, map their answers to the correct '
          'fields. (4) When you have enough, output the completed form as a clean, '
          'copyable list of "Field: Value" lines, and point out any field still '
          'missing. Be friendly, concise, and never invent personal data.'
      : 'You are a precise, helpful document assistant. The user shares a document '
          'as page images. Answer questions accurately based only on the document. '
          'If something is not in the document, say so clearly. Be concise.';

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scroll.dispose();
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
      _loadingDoc = true;
      _error = null;
      _fileName = result.files.first.name;
      _docImages = [];
      _messages.clear();
    });

    try {
      final lower = path.toLowerCase();
      if (lower.endsWith('.pdf')) {
        _isPdf = true;
        _docImages = await _renderPdf(path);
      } else {
        _isPdf = false;
        final bytes = await File(path).readAsBytes();
        final mime = lower.endsWith('.png') ? 'image/png' : 'image/jpeg';
        _docImages = [OpenRouterService.dataUrl(bytes, mime: mime)];
      }
      if (_docImages.isEmpty) {
        _error = 'Could not read any pages from this file.';
      } else if (_isForm) {
        // Kick off the form flow automatically.
        await _send(
          auto: 'Please read my form and tell me exactly what information you '
              'need from me to fill it in.',
        );
      }
    } catch (e) {
      _error = 'Could not read file: $e';
    } finally {
      if (mounted) setState(() => _loadingDoc = false);
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

  /// Build the full OpenAI-style message list. Document images are attached to
  /// the first user message so the model can see the pages.
  List<Map<String, dynamic>> _buildApiMessages() {
    final msgs = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt},
    ];
    var attached = false;
    for (final m in _messages) {
      if (m.role == 'user' && !attached && _docImages.isNotEmpty) {
        attached = true;
        msgs.add({
          'role': 'user',
          'content': [
            {'type': 'text', 'text': m.text},
            for (final url in _docImages)
              {'type': 'image_url', 'image_url': {'url': url}},
          ],
        });
      } else {
        msgs.add({'role': m.role, 'content': m.text});
      }
    }
    return msgs;
  }

  Future<void> _send({String? auto}) async {
    final text = (auto ?? _inputCtrl.text).trim();
    if (text.isEmpty || _busy) return;
    if (_docImages.isEmpty) {
      setState(() => _error = 'Choose a document first.');
      return;
    }
    setState(() {
      _messages.add(_ChatMsg('user', text));
      if (auto == null) _inputCtrl.clear();
      _busy = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final reply = await _service.chat(_buildApiMessages());
      setState(() => _messages.add(_ChatMsg('assistant', reply)));
    } on OpenRouterException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          FutureBuilder<bool>(
            future: AppSettings.instance.hasOpenRouterKey(),
            builder: (_, snap) {
              if (snap.data != true) {
                return TextButton.icon(
                  onPressed: () => context.push('/profile'),
                  icon: const Icon(Icons.key, size: 16),
                  label: const Text('Add key'),
                );
              }
              return IconButton(
                tooltip: 'AI settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push('/profile'),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _docBar(cs),
          if (_error != null) _errorBar(cs),
          Expanded(
            child: _docImages.isEmpty
                ? _emptyState(cs)
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= _messages.length) return _typingBubble(cs);
                      return _bubble(cs, _messages[i]);
                    },
                  ),
          ),
          if (_docImages.isNotEmpty) _inputBar(cs),
        ],
      ),
    );
  }

  Widget _docBar(ColorScheme cs) {
    return Material(
      color: cs.surfaceContainerHighest,
      child: InkWell(
        onTap: _loadingDoc ? null : _pick,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(children: [
            Icon(
              _fileName == null
                  ? Icons.attach_file
                  : (_isPdf ? Icons.picture_as_pdf : Icons.image),
              size: 20,
              color: cs.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _fileName ?? 'Tap to choose a PDF or image',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (_loadingDoc)
              const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            else
              Text(_fileName == null ? '' : 'Change',
                  style: TextStyle(color: cs.primary, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _errorBar(ColorScheme cs) => Container(
        width: double.infinity,
        color: cs.errorContainer.withOpacity(0.5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Icon(Icons.error_outline, size: 18, color: cs.error),
          const SizedBox(width: 8),
          Expanded(child: Text(_error!, style: TextStyle(color: cs.onErrorContainer, fontSize: 13))),
        ]),
      );

  Widget _emptyState(ColorScheme cs) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_isForm ? Icons.edit_document : Icons.auto_awesome, size: 64, color: cs.primary),
              const SizedBox(height: 16),
              Text(
                _isForm
                    ? 'Choose a form. The AI will read it and ask you for the info it needs, then fill it.'
                    : 'Choose any PDF or image, then chat to understand it, summarize, or extract details.',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _loadingDoc ? null : _pick,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose file'),
              ),
            ],
          ),
        ),
      );

  Widget _bubble(ColorScheme cs, _ChatMsg m) {
    final isUser = m.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: isUser ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(isUser ? 14 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 14),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              m.text,
              style: TextStyle(
                color: isUser ? Colors.white : cs.onSurface,
                height: 1.35,
              ),
            ),
            if (!isUser)
              GestureDetector(
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: m.text));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied')));
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.copy, size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text('Copy', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _typingBubble(ColorScheme cs) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );

  Widget _inputBar(ColorScheme cs) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: cs.surface,
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, -1))],
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _inputCtrl,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: _isForm ? 'Type your info…' : 'Ask about the document…',
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.filled(
            onPressed: _busy ? null : () => _send(),
            icon: const Icon(Icons.send),
          ),
        ]),
      ),
    );
  }
}
