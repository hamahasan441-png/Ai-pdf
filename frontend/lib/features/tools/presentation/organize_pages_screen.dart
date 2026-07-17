import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

import '../widgets/result_sheet.dart';

/// A single page in the organizer: its rendered image + rotation.
class _OrgPage {
  final Uint8List bytes;
  int rot; // quarter turns clockwise, 0..3
  _OrgPage(this.bytes, [this.rot = 0]);
}

/// Pro "Organize Pages" tool: reorder (drag), delete, rotate, and add pages
/// from other PDFs/images, then export a single PDF.
///
/// Fully offline. Pages are rendered to capped images (bounded memory) and
/// composed into a fresh PDF on export.
class OrganizePagesScreen extends StatefulWidget {
  const OrganizePagesScreen({super.key});

  @override
  State<OrganizePagesScreen> createState() => _OrganizePagesScreenState();
}

class _OrganizePagesScreenState extends State<OrganizePagesScreen> {
  static const double _renderMaxEdge = 1400;

  final List<_OrgPage> _pages = [];
  bool _busy = false;
  String _status = '';

  Future<void> _addFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      for (final f in result.files) {
        final path = f.path;
        if (path == null) continue;
        if (path.toLowerCase().endsWith('.pdf')) {
          await _addPdf(path);
        } else {
          _pages.add(_OrgPage(await File(path).readAsBytes()));
        }
      }
    } catch (e) {
      _status = l10n.couldNotAddFile(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPdf(String path) async {
    final l10n = AppLocalizations.of(context)!;
    final doc = await pdfx.PdfDocument.openFile(path);
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        setState(() => _status = l10n.loadingPageOf(i, doc.pagesCount));
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
          if (img?.bytes != null) _pages.add(_OrgPage(img!.bytes));
        } finally {
          await page.close();
        }
        await Future<void>.delayed(Duration.zero);
      }
    } finally {
      await doc.close();
      if (mounted) setState(() => _status = '');
    }
  }

  void _rotate(int index) {
    setState(() => _pages[index].rot = (_pages[index].rot + 1) % 4);
  }

  void _delete(int index) {
    setState(() => _pages.removeAt(index));
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final p = _pages.removeAt(oldIndex);
      _pages.insert(newIndex, p);
    });
  }

  /// Rotate raw image bytes by [quarterTurns] clockwise, returning PNG bytes.
  Future<Uint8List> _rotatedBytes(Uint8List src, int quarterTurns) async {
    if (quarterTurns % 4 == 0) return src;
    final codec = await ui.instantiateImageCodec(src);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final turns = quarterTurns % 4;
    final swap = turns == 1 || turns == 3;
    final w = swap ? image.height : image.width;
    final h = swap ? image.width : image.height;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.translate(w / 2, h / 2);
    canvas.rotate(turns * 3.1415926535 / 2);
    canvas.translate(-image.width / 2, -image.height / 2);
    canvas.drawImage(image, Offset.zero, Paint());
    image.dispose();
    final picture = recorder.endRecording();
    final out = await picture.toImage(w, h);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    picture.dispose();
    return data?.buffer.asUint8List() ?? src;
  }

  Future<void> _export() async {
    if (_pages.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _busy = true;
      _status = l10n.buildingPdf;
    });
    try {
      final doc = pw.Document();
      for (var i = 0; i < _pages.length; i++) {
        setState(() => _status = l10n.addingPageOf(i + 1, _pages.length));
        final p = _pages[i];
        final bytes = await _rotatedBytes(p.bytes, p.rot);
        final image = pw.MemoryImage(bytes);
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ));
        await Future<void>.delayed(Duration.zero);
      }
      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/organized_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(await doc.save());
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
        await showResultSheet(context,
            paths: [outPath], title: l10n.organizedPdf, subtitle: l10n.nPages(_pages.length));
      }
    } catch (e) {
      _status = l10n.operationFailed(e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.toolOrganize),
        actions: [
          if (_pages.isNotEmpty)
            IconButton(
              tooltip: l10n.addMore,
              icon: const Icon(Icons.add),
              onPressed: _busy ? null : _addFiles,
            ),
        ],
      ),
      body: _pages.isEmpty
          ? _empty(cs)
          : Column(
              children: [
                if (_busy && _status.isNotEmpty)
                  LinearProgressIndicator(minHeight: 3, backgroundColor: cs.surfaceContainerHighest),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(children: [
                    Text(l10n.nPages(_pages.length),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Expanded(
                      child: Text(_status.isNotEmpty ? _status : l10n.longPressToReorder,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ),
                  ]),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 90),
                    itemCount: _pages.length,
                    onReorder: _reorder,
                    itemBuilder: (context, i) => _pageTile(cs, i, key: ValueKey(_pages[i])),
                  ),
                ),
              ],
            ),
      floatingActionButton: _pages.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.check),
              label: Text(l10n.exportPdf),
            ),
    );
  }

  Widget _empty(ColorScheme cs) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dashboard_customize_outlined, size: 72, color: cs.primary),
              const SizedBox(height: 16),
              Text(l10n.organizeYourPages,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              const SizedBox(height: 6),
              Text(
                l10n.organizeYourPagesBody,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy ? null : _addFiles,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(l10n.addFiles),
              ),
            ],
          ),
        ),
      );
  }

  Widget _pageTile(ColorScheme cs, int i, {required Key key}) {
    final p = _pages[i];
    final l10n = AppLocalizations.of(context)!;
    return Card(
      key: key,
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          // Thumbnail (decoded small to bound memory)
          Container(
            width: 60,
            height: 80,
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(6),
            ),
            clipBehavior: Clip.antiAlias,
            child: RotatedBox(
              quarterTurns: p.rot,
              child: Image.memory(p.bytes, fit: BoxFit.cover, cacheWidth: 160),
            ),
          ),
          const SizedBox(width: 14),
          Text(l10n.pageNumber(i + 1), style: const TextStyle(fontWeight: FontWeight.w600)),
          const Spacer(),
          IconButton(
            tooltip: l10n.rotate,
            icon: const Icon(Icons.rotate_right),
            onPressed: () => _rotate(i),
          ),
          IconButton(
            tooltip: l10n.delete,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => _delete(i),
          ),
          ReorderableDragStartListener(
            index: i,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.drag_handle),
            ),
          ),
        ]),
      ),
    );
  }
}
