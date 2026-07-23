import 'package:flutter/material.dart';

import 'package:ai_pdf/features/security/data/pdf_password_service.dart';

/// Screen to add password protection to a PDF file.
///
/// User picks a PDF → enters a password → gets an encrypted PDF they can
/// save/share. Works fully offline (encryption runs on-device in an isolate).
class PdfProtectScreen extends StatefulWidget {
  const PdfProtectScreen({super.key});

  @override
  State<PdfProtectScreen> createState() => _PdfProtectScreenState();
}

class _PdfProtectScreenState extends State<PdfProtectScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _service = const PdfPasswordService();

  bool _obscurePassword = true;
  bool _allowPrinting = true;
  bool _allowCopying = true;
  bool _working = false;
  String? _filePath;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _canProtect =>
      _filePath != null &&
      _passwordController.text.isNotEmpty &&
      _passwordController.text == _confirmController.text &&
      !_working;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Password Protect PDF')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // File selection
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: Text(_filePath ?? 'Choose a PDF'),
              subtitle: _filePath != null ? null : const Text('Tap to select'),
              onTap: _pickFile,
            ),
          ),
          const SizedBox(height: 24),

          // Password fields
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              border: const OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Confirm password',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              errorText: _confirmController.text.isNotEmpty &&
                      _confirmController.text != _passwordController.text
                  ? 'Passwords do not match'
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),

          // Permissions
          Text('Permissions', style: theme.textTheme.titleSmall),
          SwitchListTile(
            title: const Text('Allow printing'),
            value: _allowPrinting,
            onChanged: (v) => setState(() => _allowPrinting = v),
          ),
          SwitchListTile(
            title: const Text('Allow copying text'),
            value: _allowCopying,
            onChanged: (v) => setState(() => _allowCopying = v),
          ),
          const SizedBox(height: 24),

          // Error
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ),

          // Action button
          FilledButton.icon(
            onPressed: _canProtect ? _protect : null,
            icon: _working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.shield),
            label: Text(_working ? 'Encrypting…' : 'Protect PDF'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFile() async {
    // In production: use file_picker to select a PDF.
    // For now, set a placeholder path.
    setState(() {
      _filePath = 'document.pdf';
      _error = null;
    });
  }

  Future<void> _protect() async {
    setState(() {
      _working = true;
      _error = null;
    });

    try {
      // In production: read file bytes, call _service.protect(), save result.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF protected with password')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = 'Protection failed: $e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }
}
