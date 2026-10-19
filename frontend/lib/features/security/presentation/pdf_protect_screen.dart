import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:ai_pdf/core/utils/error_text.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

import 'package:ai_pdf/core/services/tool_handoff.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/security/data/pdf_encryptor.dart';
import 'package:ai_pdf/features/security/data/pdf_password_service.dart';
import 'package:ai_pdf/features/tools/widgets/result_sheet.dart';

/// Pick a PDF, choose a password (and optional limits), get an encrypted
/// copy. Fully offline.
class PdfProtectScreen extends StatefulWidget {
  const PdfProtectScreen({super.key});

  @override
  State<PdfProtectScreen> createState() => _PdfProtectScreenState();
}

class _PdfProtectScreenState extends State<PdfProtectScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  static const _service = PdfPasswordService();

  bool _obscure = true;
  bool _allowPrinting = true;
  bool _allowCopying = true;
  bool _working = false;
  String? _filePath;
  String? _error;

  @override
  void initState() {
    super.initState();
    // A file handed over from another screen (e.g. after an editor export).
    final handed = ToolHandoff.instance.take();
    if (handed != null && handed.toLowerCase().endsWith('.pdf')) _filePath = handed;
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _matches => _password.text == _confirm.text;
  bool get _canProtect => _filePath != null && _password.text.isNotEmpty && _matches && !_working;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;
    setState(() {
      _filePath = path;
      _error = null;
    });
  }

  Future<void> _protect() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final out = await _service.protectFile(
        sourcePath: _filePath!,
        password: _password.text,
        access: PdfAccess(print: _allowPrinting, copy: _allowCopying),
      );
      if (!mounted) return;
      await showResultSheet(context, paths: [out], title: l10n.protectDone, subtitle: l10n.protectDoneSub);
    } on PdfSourceException catch (e) {
      setState(() => _error = e.encrypted ? l10n.protectAlreadyEncrypted : l10n.operationFailed(e.message));
    } catch (e) {
      setState(() => _error = l10n.operationFailed(describeError(e, l10n)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.toolProtect)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: Text(
                _filePath?.split('/').last ?? l10n.tapToChoosePdf,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.folder_open),
              onTap: _working ? null : _pickFile,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.protectPassword,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _confirm,
            obscureText: _obscure,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.protectConfirm,
              border: const OutlineInputBorder(),
              errorText: _confirm.text.isNotEmpty && !_matches ? l10n.protectMismatch : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            title: Text(l10n.protectAllowPrint),
            value: _allowPrinting,
            onChanged: (v) => setState(() => _allowPrinting = v),
          ),
          SwitchListTile(
            title: Text(l10n.protectAllowCopy),
            value: _allowCopying,
            onChanged: (v) => setState(() => _allowCopying = v),
          ),
          if (!_allowPrinting || !_allowCopying)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l10n.protectRestrictNote, style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.protectForgetWarning, style: theme.textTheme.bodySmall)),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _canProtect ? _protect : null,
            icon: _working
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.lock),
            label: Text(l10n.protectButton),
          ),
        ],
      ),
    );
  }
}
