import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../../core/services/ocr_service.dart';
import '../services/offline_pdf_service.dart';

/// Read Aloud — extract a document's text (on-device OCR) and speak it with the
/// system TTS engine. Fully offline; no extra permissions.
class ReadAloudScreen extends StatefulWidget {
  const ReadAloudScreen({super.key});
  @override
  State<ReadAloudScreen> createState() => _ReadAloudScreenState();
}

class _ReadAloudScreenState extends State<ReadAloudScreen> {
  final FlutterTts _tts = FlutterTts();
  String? _fileName;
  String? _text;
  bool _busy = false;
  bool _playing = false;
  double _rate = 0.5;

  @override
  void initState() {
    super.initState();
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _playing = false);
    });
    _tts.setCancelHandler(() {
      if (mounted) setState(() => _playing = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _tts.stop();
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
    final l10n = AppLocalizations.of(context)!;

    await _tts.stop();
    setState(() {
      _busy = true;
      _playing = false;
      _text = null;
      _fileName = result.files.first.name;
    });
    try {
      String text;
      if (path.toLowerCase().endsWith('.pdf')) {
        final outPath = await OfflinePdfService.instance.pdfToText(path);
        text = await File(outPath).readAsString();
      } else {
        final ocr = OcrService();
        try {
          text = await ocr.recognizeText(path);
        } finally {
          await ocr.dispose();
        }
      }
      text = text.trim();
      setState(() => _text = text.isEmpty ? null : text);
      if (text.isEmpty && mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.nothingToRead)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.operationFailed(e.toString()))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle() async {
    if (_text == null) return;
    if (_playing) {
      await _tts.stop();
      if (mounted) setState(() => _playing = false);
    } else {
      await _tts.setSpeechRate(_rate);
      setState(() => _playing = true);
      await _tts.speak(_text!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.readAloud)),
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
                  border: Border.all(color: _text != null ? cs.primary : cs.outlineVariant, width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(children: [
                  Icon(_fileName == null ? Icons.headphones_outlined : Icons.description,
                      size: 48, color: cs.primary),
                  const SizedBox(height: 12),
                  Text(
                    _fileName ?? l10n.chooseFileToRead,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            if (_busy)
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Text(l10n.extractingText),
              ]),
            if (_text != null) ...[
              Row(children: [
                Icon(Icons.speed, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(l10n.speed, style: TextStyle(color: cs.onSurfaceVariant)),
                Expanded(
                  child: Slider(
                    value: _rate,
                    min: 0.2,
                    max: 1.0,
                    onChanged: (v) => setState(() => _rate = v),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SingleChildScrollView(
                    child: Text(_text!, style: const TextStyle(fontSize: 13, height: 1.5)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _toggle,
                icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
                label: Text(_playing ? l10n.stop : l10n.play),
              ),
            ] else if (!_busy)
              const Spacer(),
          ],
        ),
      ),
    );
  }
}
