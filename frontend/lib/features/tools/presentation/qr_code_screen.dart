import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:ai_pdf/features/tools/services/qr_code_service.dart';

/// QR Code tool — generate QR codes from text/URLs and embed them into PDFs.
///
/// User enters text → sees live QR preview → can save as image or insert into
/// the editor as a stamp annotation.
class QrCodeScreen extends StatefulWidget {
  const QrCodeScreen({super.key});

  @override
  State<QrCodeScreen> createState() => _QrCodeScreenState();
}

class _QrCodeScreenState extends State<QrCodeScreen> {
  final _controller = TextEditingController();
  final _service = const QrCodeService();
  Uint8List? _qrImage;
  bool _generating = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _generating = true);
    try {
      final image = await _service.generateQrImage(data: text, size: 512);
      setState(() => _qrImage = image);
    } finally {
      setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('QR Code Generator')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Text or URL',
              hintText: 'https://example.com',
              prefixIcon: Icon(Icons.qr_code),
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
            onSubmitted: (_) => _generate(),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _generating ? null : _generate,
            icon: _generating
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.qr_code_2),
            label: const Text('Generate QR Code'),
          ),
          const SizedBox(height: 24),
          if (_qrImage != null) ...[
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Image.memory(_qrImage!, width: 200, height: 200),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _controller.text));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Text copied')),
                    );
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy text'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _qrImage),
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Insert into PDF'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
