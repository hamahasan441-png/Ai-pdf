import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../core/services/ocr_service.dart';
import '../../../core/services/user_profile_service.dart';
import '../models/filled_field.dart';
import '../services/smart_form_filler.dart';
import 'pick_edit_screen.dart';

/// Offline Smart Form Filler — no AI API, everything on-device.
///
/// Two steps:
///   1. Upload the blank FORM (PDF or photo).
///   2. Upload an INFO document that contains your details (ID, certificate,
///      a previous form, a CV…).
/// The app OCRs both, understands the form's fields (German + English), pulls
/// the matching values out of your info document, and opens the editor with the
/// answers already placed so you can review, adjust and export.
class SmartFillScreen extends StatefulWidget {
  const SmartFillScreen({super.key});

  @override
  State<SmartFillScreen> createState() => _SmartFillScreenState();
}

class _SmartFillScreenState extends State<SmartFillScreen> {
  static const int _maxPages = 15;
  static const double _renderMaxEdge = 1400;

  String? _formPath;
  String? _formName;
  String? _infoPath;
  String? _infoName;
  bool _busy = false;
  bool _profileHasData = false;
  String? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfileFlag();
  }

  /// So the info document can be optional: if the saved profile has anything,
  /// the form can be filled from it alone (fully standalone, one upload).
  Future<void> _loadProfileFlag() async {
    await UserProfileService.instance.load();
    final has =
        UserProfileService.instance.data.values.any((v) => v.trim().isNotEmpty);
    if (mounted) setState(() => _profileHasData = has);
  }

  Future<void> _pickForm() async {
    final picked = await _pickFile();
    if (picked == null) return;
    setState(() {
      _formPath = picked.$1;
      _formName = picked.$2;
      _error = null;
    });
  }

  Future<void> _pickInfo() async {
    final picked = await _pickFile();
    if (picked == null) return;
    setState(() {
      _infoPath = picked.$1;
      _infoName = picked.$2;
      _error = null;
    });
  }

  Future<(String, String)?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return null;
    final path = result.files.first.path;
    if (path == null) return null;
    return (path, result.files.first.name);
  }

  Future<void> _run() async {
    final formPath = _formPath;
    final infoPath = _infoPath;
    if (formPath == null || _busy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _error = null;
      _status = l10n.readingTheForm;
    });
    try {
      final formPages = await _ocrDocument(formPath);
      // The info document is optional — when it's omitted we fill straight from
      // the user's saved on-device profile (no second upload needed).
      List<OcrResult> infoPages = const [];
      if (infoPath != null) {
        if (!mounted) return;
        setState(() => _status = l10n.smartFillReadingInfo);
        infoPages = await _ocrDocument(infoPath);
      }

      await UserProfileService.instance.load();
      final profile = UserProfileService.instance.data;

      if (!mounted) return;
      setState(() => _status = l10n.smartFillMatching);
      final info = SmartFormFiller.extractInfo(infoPages);
      final fields = SmartFormFiller.fillForm(formPages, info, profile);

      if (!mounted) return;
      if (fields.isEmpty) {
        setState(() => _error = l10n.smartFillNoMatch);
        return;
      }

      // Show the review sheet so the user can verify, untick or edit values
      // before they are placed on the form.
      setState(() => _busy = false);
      if (!mounted) return;
      final confirmed = await showModalBottomSheet<List<FilledField>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (ctx) => _ReviewSheet(fields: fields),
      );
      if (confirmed == null || confirmed.isEmpty || !mounted) return;

      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            PickEditScreen(initialPath: formPath, initialFields: confirmed),
      ));
      if (mounted) {
        setState(() => _status = l10n.smartFillPlaced(confirmed.length));
      }
    } catch (e) {
      if (mounted) setState(() => _error = l10n.operationFailed(e.toString()));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Render a PDF/image to page images and OCR each, fully on-device.
  Future<List<OcrResult>> _ocrDocument(String path) async {
    final ocr = OcrService();
    final results = <OcrResult>[];
    try {
      if (path.toLowerCase().endsWith('.pdf')) {
        final tmp = await getTemporaryDirectory();
        final stamp = DateTime.now().microsecondsSinceEpoch;
        final doc = await pdfx.PdfDocument.openFile(path);
        try {
          final count = doc.pagesCount < _maxPages ? doc.pagesCount : _maxPages;
          for (var i = 1; i <= count; i++) {
            final page = await doc.getPage(i);
            try {
              final longEdge =
                  page.width > page.height ? page.width : page.height;
              final scale =
                  longEdge > _renderMaxEdge ? _renderMaxEdge / longEdge : 1.0;
              final img = await page.render(
                width: page.width * scale,
                height: page.height * scale,
                format: pdfx.PdfPageImageFormat.jpeg,
                backgroundColor: '#FFFFFF',
              );
              final bytes = img?.bytes;
              if (bytes != null) {
                final p = '${tmp.path}/sf_${stamp}_$i.jpg';
                await File(p).writeAsBytes(bytes);
                results.add(await ocr.recognize(p));
                try {
                  await File(p).delete();
                } catch (_) {}
              } else {
                results.add(const OcrResult('', []));
              }
            } finally {
              await page.close();
            }
          }
        } finally {
          await doc.close();
        }
      } else {
        results.add(await ocr.recognize(path));
      }
    } finally {
      await ocr.dispose();
    }
    return results;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final ready = _formPath != null && (_infoPath != null || _profileHasData);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.smartFormFiller)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(0.35),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Icon(Icons.offline_bolt, color: cs.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.smartFillIntro,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurface),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 18),
          _stepCard(
            cs,
            step: '1',
            icon: Icons.description_outlined,
            title: l10n.smartFillFormStep,
            fileName: _formName,
            actionLabel: _formName == null ? l10n.chooseFile : l10n.change,
            onTap: _busy ? null : _pickForm,
          ),
          const SizedBox(height: 12),
          _stepCard(
            cs,
            step: '2',
            icon: Icons.badge_outlined,
            title: l10n.smartFillInfoStep,
            fileName: _infoName,
            actionLabel: _infoName == null ? l10n.chooseFile : l10n.change,
            emptyLabel: _profileHasData ? l10n.smartFillInfoOptional : null,
            onTap: _busy ? null : _pickInfo,
          ),
          const SizedBox(height: 20),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.errorContainer.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Icon(Icons.error_outline, size: 18, color: cs.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: TextStyle(color: cs.onErrorContainer, fontSize: 13)),
                ),
              ]),
            ),
          FilledButton.icon(
            onPressed: ready && !_busy ? _run : null,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.auto_fix_high),
            label: Text(_busy ? (_status ?? l10n.working) : l10n.smartFillRun),
          ),
          if (!_busy && _status != null) ...[
            const SizedBox(height: 10),
            Text(_status!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }

  Widget _stepCard(
    ColorScheme cs, {
    required String step,
    required IconData icon,
    required String title,
    required String? fileName,
    required String actionLabel,
    required VoidCallback? onTap,
    String? emptyLabel,
  }) {
    final chosen = fileName != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: chosen ? cs.primary : cs.outlineVariant,
              width: chosen ? 1.5 : 1),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: cs.primary,
            child: Text(step,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: cs.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  fileName ??
                      emptyLabel ??
                      AppLocalizations.of(context)!.smartFillNotChosen,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      color: chosen ? cs.primary : cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Text(actionLabel,
              style: TextStyle(
                  color: cs.primary, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}



/// A review sheet shown after the engine matches fields, before placing them.
/// The user can untick fields they don't want, edit values inline, and see which
/// ones are uncertain (low confidence). Dismissing returns the confirmed list;
/// swiping away / tapping outside returns null (cancel).
class _ReviewSheet extends StatefulWidget {
  final List<FilledField> fields;
  const _ReviewSheet({required this.fields});

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late List<bool> _checked;
  late List<FilledField> _fields;

  @override
  void initState() {
    super.initState();
    _fields = List.of(widget.fields);
    _checked = List.filled(_fields.length, true);
  }

  void _editField(int i) async {
    final ctrl = TextEditingController(text: _fields[i].text);
    final l10n = AppLocalizations.of(context)!;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_fields[i].field.isNotEmpty ? _fields[i].field : l10n.editText),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: l10n.typeHere,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(l10n.ok)),
        ],
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      setState(() => _fields[i] = _fields[i].withText(result.trim()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final count = _checked.where((c) => c).length;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Title bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Icon(Icons.checklist, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.reviewBeforePlacing,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(l10n.editAnyValue,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ),
            const SizedBox(height: 8),
            // Field list
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _fields.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  final f = _fields[i];
                  return ListTile(
                    leading: Checkbox(
                      value: _checked[i],
                      onChanged: (v) =>
                          setState(() => _checked[i] = v ?? false),
                    ),
                    title: Text(
                      f.field.isNotEmpty ? f.field : f.anchor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _checked[i] ? cs.onSurface : cs.outline,
                      ),
                    ),
                    subtitle: Text(
                      f.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: _checked[i] ? cs.primary : cs.outline,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (f.uncertain)
                          Tooltip(
                            message: l10n.smartFillUncertain,
                            child: Icon(Icons.warning_amber_rounded,
                                size: 18, color: cs.error),
                          ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          tooltip: l10n.editText,
                          onPressed: _checked[i] ? () => _editField(i) : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Place button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: count > 0
                    ? () {
                        final result = <FilledField>[];
                        for (var i = 0; i < _fields.length; i++) {
                          if (_checked[i]) result.add(_fields[i]);
                        }
                        Navigator.pop(context, result);
                      }
                    : null,
                icon: const Icon(Icons.check),
                label: Text(l10n.placeNValues(count)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
