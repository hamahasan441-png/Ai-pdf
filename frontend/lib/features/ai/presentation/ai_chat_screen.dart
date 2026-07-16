import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_settings.dart';
import '../../../core/network/openrouter_service.dart';
import '../../../core/services/form_memory_service.dart';
import '../../../core/services/ocr_service.dart';
import '../../../core/services/user_profile_service.dart';
import '../../tools/models/filled_field.dart';
import '../../tools/presentation/pick_edit_screen.dart';
import '../../tools/widgets/result_sheet.dart';

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
  // A3: send the whole document (bounded for memory/cost). Most forms/letters
  // are a few pages; capped resolution keeps each page light.
  static const int _maxPages = 12;
  static const double _renderMaxEdge = 1200;

  final _service = OpenRouterService();
  final _inputCtrl = TextEditingController();
  final _scroll = ScrollController();

  String? _fileName;
  String? _docPath; // original file path (for placing answers back on the form)
  bool _isPdf = false;
  List<String> _docImages = []; // data URLs attached to the first user turn
  List<String> _pageImagePaths = []; // on-disk page images (for OCR anchoring)
  bool _placing = false;

  final List<_ChatMsg> _messages = [];
  bool _busy = false;
  bool _streaming = false;
  bool _loadingDoc = false;
  String? _error;

  String _profileBlock = ''; // the user's saved details, injected for form-fill
  String _memoryBlock = ''; // previously-answered fields, injected for form-fill

  bool get _isForm => widget.mode == AiChatMode.fillForm;

  String get _title => _isForm ? 'Fill Form with AI' : 'Understand with AI';

  String get _systemPrompt {
    if (_isForm) {
      final profile = _profileBlock.isNotEmpty
          ? '\n\nThe user has this saved profile — use it to PRE-FILL any matching '
              'fields automatically, and do NOT ask again for information already '
              'present here:\n$_profileBlock'
          : '';
      final memory = _memoryBlock.isNotEmpty
          ? '\n\nThe user has previously answered these fields on earlier forms — '
              'reuse a value ONLY when it clearly matches a field on this form, and '
              'confirm rather than assume when unsure:\n$_memoryBlock'
          : '';
      return 'You are an expert form-filling assistant. The user shares a form as page '
          'images. Steps: (1) Read the form carefully and identify every field or '
          'blank that needs a value. (2) Pre-fill everything you already know from '
          'the profile below. (3) Ask the user only for the remaining fields, grouped '
          'logically and in plain language. (4) When you have enough, output the '
          'completed form as a clean, copyable list of "Field: Value" lines, and point '
          'out any field still missing. Be friendly, concise, and never invent '
          'personal data.$profile$memory';
    }
    return 'You are a precise, helpful document assistant. The user shares a document '
        'as page images. Answer questions accurately based only on the document. '
        'If something is not in the document, say so clearly. Be concise.';
  }

  @override
  void initState() {
    super.initState();
    if (_isForm) {
      UserProfileService.instance.load().then((_) {
        if (mounted) setState(() => _profileBlock = UserProfileService.instance.asPromptBlock());
      });
      FormMemoryService.instance.load().then((_) {
        if (mounted) setState(() => _memoryBlock = FormMemoryService.instance.asPromptBlock());
      });
    }
  }

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
      _docPath = path;
      _docImages = [];
      _pageImagePaths = [];
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
        _pageImagePaths = [path]; // the image itself is page 1 for OCR
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
    _pageImagePaths = [];
    Directory? tmp;
    try {
      tmp = await getTemporaryDirectory();
    } catch (_) {
      tmp = null;
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
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
            // Persist the page image so OCR can anchor placement precisely.
            if (tmp != null) {
              try {
                final p = '${tmp.path}/aiform_${stamp}_p$i.jpg';
                await File(p).writeAsBytes(bytes);
                _pageImagePaths.add(p);
              } catch (_) {
                // OCR anchoring is best-effort; ignore write failures.
              }
            }
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

  /// Run on-device OCR on each rendered page, returning page (1-based) → lines.
  /// Best-effort: returns an empty map if OCR is unavailable or fails.
  Future<Map<int, List<OcrLine>>> _ocrPages() async {
    final byPage = <int, List<OcrLine>>{};
    if (_pageImagePaths.isEmpty) return byPage;
    final ocr = OcrService();
    try {
      for (var i = 0; i < _pageImagePaths.length; i++) {
        try {
          final res = await ocr.recognize(_pageImagePaths[i]);
          byPage[i + 1] = res.lines;
        } catch (_) {
          // Skip pages that fail OCR.
        }
      }
    } finally {
      await ocr.dispose();
    }
    return byPage;
  }

  /// Build a compact prompt block of detected label boxes for the AI to anchor
  /// placement against. Keeps only label-like lines, capped per page.
  String _anchorPrompt(Map<int, List<OcrLine>> byPage) {
    if (byPage.isEmpty) return '';
    final b = StringBuffer();
    byPage.forEach((page, lines) {
      var count = 0;
      for (final l in lines) {
        final t = l.text.trim().replaceAll('"', '');
        if (t.isEmpty) continue;
        // Prefer short labels or anything ending in a colon.
        if (t.length > 40 && !t.contains(':')) continue;
        b.writeln('p$page: "$t" (x${l.x.toStringAsFixed(2)},y${l.y.toStringAsFixed(2)})');
        if (++count >= 40) break;
      }
    });
    final s = b.toString();
    if (s.isEmpty) return '';
    return '\n\nDetected text labels on the pages (normalized coordinates). Use these '
        'to place each value ACCURATELY: set "anchor" to the EXACT label text you '
        'are filling next to so the value lands on the correct line:\n$s';
  }

  /// Snap a parsed field onto its matching OCR label box (just to the right of
  /// the label, vertically aligned). Returns the field unchanged if no match.
  List<FilledField> _snapToOcr(List<FilledField> fields, Map<int, List<OcrLine>> byPage) {
    if (byPage.isEmpty) return fields;
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final out = <FilledField>[];
    for (final f in fields) {
      final lines = byPage[f.page];
      if (f.anchor.isEmpty || lines == null || lines.isEmpty) {
        out.add(f);
        continue;
      }
      final a = norm(f.anchor);
      OcrLine? best;
      var bestScore = 0;
      for (final l in lines) {
        final t = norm(l.text);
        if (t.isEmpty) continue;
        var score = 0;
        if (t == a) {
          score = 1000;
        } else if (t.contains(a) || a.contains(t)) {
          score = a.length < t.length ? a.length : t.length;
        }
        if (score > bestScore) {
          bestScore = score;
          best = l;
        }
      }
      if (best != null && bestScore > 0) {
        final nx = (best.x + best.w + 0.012).clamp(0.0, 0.97);
        final ny = best.y.clamp(0.0, 0.97);
        out.add(f.withXY(nx.toDouble(), ny.toDouble()));
      } else {
        out.add(f);
      }
    }
    return out;
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

    // Build request BEFORE adding the assistant placeholder.
    final apiMessages = _buildApiMessages();
    final assistant = _ChatMsg('assistant', '');
    setState(() {
      _messages.add(assistant);
      _streaming = true;
    });

    try {
      await _service.chatStream(apiMessages, onDelta: (d) {
        if (!mounted) return;
        setState(() => assistant.text += d);
        _scrollToBottom();
      });
      // Safety net: if nothing streamed, try a normal call.
      if (assistant.text.trim().isEmpty) {
        final reply = await _service.chat(apiMessages);
        if (mounted) setState(() => assistant.text = reply);
      }
    } on OpenRouterException catch (e) {
      // Streaming failed — try a normal (non-stream) call once before erroring.
      try {
        final reply = await _service.chat(apiMessages);
        if (mounted) setState(() => assistant.text = reply);
      } catch (_) {
        if (mounted) {
          setState(() {
            _messages.remove(assistant);
            _error = e.message;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.remove(assistant);
          _error = 'Something went wrong: $e';
        });
      }
    } finally {
      if (mounted) setState(() {
            _busy = false;
            _streaming = false;
          });
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

  /// Ask the AI for the filled values WITH positions, then open the editor with
  /// those values pre-placed on the actual form so the user can review/adjust
  /// and export a real filled PDF.
  Future<void> _placeOnForm() async {
    if (_docPath == null || _docImages.isEmpty || _placing) return;
    setState(() {
      _placing = true;
      _error = null;
    });
    try {
      // On-device OCR gives real label positions so placement is precise
      // instead of the model guessing pixel coordinates.
      final ocrByPage = await _ocrPages();
      final anchorBlock = _anchorPrompt(ocrByPage);

      // Add a hidden instruction turn requesting strict JSON with coordinates.
      final jsonMessages = _buildApiMessages()
        ..add({
          'role': 'user',
          'content':
              'Now output ONLY a JSON array (no prose, no code fences) of the values '
              'to write on the form based on everything above. Each item: '
              '{"field": "<short label of the field>", "page": <1-based page number>, '
              '"x": <0..1 from left edge>, "y": <0..1 from top edge>, '
              '"text": "<value to write>", '
              '"type": "text" | "check" | "signature", '
              '"confidence": "high" | "low", '
              '"anchor": "<exact detected label text to place next to, or empty>"}. '
              'Use type "check" for checkboxes/radios that should be ticked (set text '
              'to "yes"); omit boxes that stay empty. Use type "signature" for '
              'signature lines and set text to the person\'s full name. Set confidence '
              '"low" for any value or position you are unsure about. Place each value '
              'where its blank/answer line is on the page. Only include fields you have '
              'a value for.$anchorBlock',
        });

      final reply = await _service.chat(jsonMessages);
      final fields = _snapToOcr(_parseFields(reply), ocrByPage);

      if (fields.isEmpty) {
        setState(() => _error =
            'Could not detect where to place the answers. You can still copy the '
            'values above and place them manually in the editor.');
        return;
      }

      if (!mounted) return;
      // A4: review & confirm before placing.
      final confirmed = await showModalBottomSheet<List<FilledField>>(
        context: context,
        isScrollControlled: true,
        builder: (_) => _FieldReviewSheet(fields: fields),
      );
      if (confirmed == null || confirmed.isEmpty) return;

      // Remember the confirmed answers so recurring fields auto-fill next time.
      final toRemember = <String, String>{};
      for (final f in confirmed) {
        if (f.field.trim().isNotEmpty && f.text.trim().isNotEmpty) {
          toRemember[f.field] = f.text;
        }
      }
      if (toRemember.isNotEmpty) {
        FormMemoryService.instance.remember(toRemember).then((_) {
          if (mounted) {
            setState(() => _memoryBlock = FormMemoryService.instance.asPromptBlock());
          }
        });
      }

      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PickEditScreen(initialPath: _docPath, initialFields: confirmed),
      ));
    } on OpenRouterException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Could not place answers: $e');
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  /// Extract a list of FilledField from a possibly-messy AI reply.
  List<FilledField> _parseFields(String reply) {
    final result = <FilledField>[];
    // Find the JSON array within the reply (strip prose / code fences).
    final start = reply.indexOf('[');
    final end = reply.lastIndexOf(']');
    if (start < 0 || end <= start) return result;
    final jsonStr = reply.substring(start, end + 1);
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is List) {
        for (final item in decoded) {
          final f = FilledField.tryParse(item);
          if (f != null) result.add(f);
        }
      }
    } catch (_) {
      // Malformed JSON — return whatever we parsed (possibly empty).
    }
    return result;
  }

  /// Save an AI answer as a shareable PDF (and record it in Recent Files).
  Future<void> _saveAnswerPdf(String text) async {
    try {
      final doc = pw.Document();
      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => [
          pw.Header(level: 0, text: 'AI PDF — Notes'),
          pw.SizedBox(height: 8),
          pw.Paragraph(text: text),
        ],
      ));
      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/ai_notes_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(await doc.save());
      if (mounted) {
        await showResultSheet(context,
            paths: [outPath], title: 'AI Answer', subtitle: 'Saved as PDF');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save PDF: $e');
    }
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
                  onPressed: () => context.push('/settings'),
                  icon: const Icon(Icons.key, size: 16),
                  label: const Text('Add key'),
                );
              }
              return IconButton(
                tooltip: 'AI settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push('/settings'),
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
                : (_messages.isEmpty && !_isForm && !_busy
                    ? _suggestionView(cs)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        // Show the extra typing bubble only when busy AND not
                        // already streaming into an assistant bubble.
                        itemCount: _messages.length + ((_busy && !_streaming) ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= _messages.length) return _typingBubble(cs);
                          return _bubble(cs, _messages[i]);
                        },
                      )),
          ),
          if (_isForm && _docImages.isNotEmpty && _messages.length >= 2)
            _placeBar(cs),
          if (_docImages.isNotEmpty) _inputBar(cs),
        ],
      ),
    );
  }

  Widget _placeBar(ColorScheme cs) {
    return Material(
      color: cs.primaryContainer.withOpacity(0.4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _placing ? null : _placeOnForm,
            icon: _placing
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_fix_high),
            label: Text(_placing ? 'Placing answers…' : 'Place answers on the form'),
          ),
        ),
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
            if (!isUser && m.text.isEmpty)
              const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              SelectableText(
                m.text,
                style: TextStyle(
                  color: isUser ? Colors.white : cs.onSurface,
                  height: 1.35,
                ),
              ),
            // Copy / Save actions only once the answer has content.
            if (!isUser && m.text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  _bubbleAction(cs, Icons.copy, 'Copy', () async {
                    await Clipboard.setData(ClipboardData(text: m.text));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Copied')));
                    }
                  }),
                  const SizedBox(width: 14),
                  _bubbleAction(cs, Icons.picture_as_pdf_outlined, 'Save PDF',
                      () => _saveAnswerPdf(m.text)),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bubbleAction(ColorScheme cs, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ]),
    );
  }

  /// Shown in Understand mode after a doc is loaded but before any question,
  /// to give the user quick starting points.
  Widget _suggestionView(ColorScheme cs) {
    const suggestions = [
      'Summarize this document',
      'List the key dates, names and amounts',
      'Explain it in simple words',
      'What do I need to do or send?',
      'Are there any deadlines?',
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Icon(Icons.auto_awesome, size: 40, color: cs.primary),
        const SizedBox(height: 10),
        Text('Ask about your document, or tap a suggestion:',
            textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: suggestions
              .map((s) => ActionChip(
                    label: Text(s),
                    onPressed: () {
                      if (!_busy) _send(auto: s);
                    },
                  ))
              .toList(),
        ),
      ],
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

/// Review & confirm sheet shown before placing answers on the form.
/// Lets the user edit each value and untick ones they don't want placed.
class _FieldReviewSheet extends StatefulWidget {
  final List<FilledField> fields;
  const _FieldReviewSheet({required this.fields});

  @override
  State<_FieldReviewSheet> createState() => _FieldReviewSheetState();
}

class _FieldReviewSheetState extends State<_FieldReviewSheet> {
  late final List<TextEditingController> _ctrls;
  late final List<bool> _include;

  @override
  void initState() {
    super.initState();
    _ctrls = widget.fields.map((f) => TextEditingController(text: f.text)).toList();
    _include = List<bool>.filled(widget.fields.length, true);
  }

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    final out = <FilledField>[];
    for (var i = 0; i < widget.fields.length; i++) {
      if (!_include[i]) continue;
      final v = _ctrls[i].text.trim();
      if (v.isEmpty) continue;
      out.add(widget.fields[i].withText(v));
    }
    Navigator.pop(context, out);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final count = _include.where((e) => e).length;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (context, scrollCtrl) => Column(
        children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: cs.outlineVariant, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Icon(Icons.fact_check_outlined, color: cs.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Review before placing',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Edit any value or untick what you don\'t want. Then place them on the form.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.separated(
              controller: scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: widget.fields.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final f = widget.fields[i];
                IconData typeIcon = Icons.text_fields;
                if (f.isCheck) typeIcon = Icons.check_box_outlined;
                if (f.isSignature) typeIcon = Icons.draw_outlined;
                return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Checkbox(
                    value: _include[i],
                    onChanged: (v) => setState(() => _include[i] = v ?? true),
                  ),
                  Tooltip(
                    message: f.isCheck
                        ? 'Checkbox'
                        : (f.isSignature ? 'Signature' : 'Text'),
                    child: Icon(typeIcon, size: 18, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _ctrls[i],
                      decoration: InputDecoration(
                        labelText: f.field.isNotEmpty ? f.field : 'Value (page ${f.page})',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        suffixIcon: f.uncertain
                            ? Tooltip(
                                message: 'AI was unsure — please double-check',
                                child: Icon(Icons.warning_amber_rounded,
                                    size: 20, color: Colors.orange.shade700),
                              )
                            : null,
                      ),
                    ),
                  ),
                ]);
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: count == 0 ? null : _confirm,
                    icon: const Icon(Icons.auto_fix_high),
                    label: Text('Place $count value(s)'),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
