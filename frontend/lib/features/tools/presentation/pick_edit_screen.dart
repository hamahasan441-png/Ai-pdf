import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Offline PDF/Image Editor.
///
/// Fully on-device: pick a PDF or image, draw/sign/annotate on it,
/// then export as a flattened PDF. No backend, no internet.
class PickEditScreen extends StatefulWidget {
  const PickEditScreen({super.key});
  @override
  State<PickEditScreen> createState() => _PickEditScreenState();
}

class _PickEditScreenState extends State<PickEditScreen> {
  Uint8List? _pageImage; // rendered page/image to annotate
  final List<List<Offset>> _strokes = [];
  List<Offset> _current = [];
  Color _color = Colors.red;
  double _stroke = 3;
  bool _busy = false;
  final GlobalKey _canvasKey = GlobalKey();

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path!;
    setState(() => _busy = true);

    try {
      if (path.toLowerCase().endsWith('.pdf')) {
        // Rasterize first PDF page to image (offline)
        final bytes = await File(path).readAsBytes();
        await for (final page in Printing.raster(bytes, pages: [0], dpi: 150)) {
          final png = await page.toPng();
          setState(() => _pageImage = png);
          break;
        }
      } else {
        // Image: load directly
        setState(() => _pageImage = File(path).readAsBytesSync());
      }
      _strokes.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open file: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    if (_pageImage == null) return;
    setState(() => _busy = true);
    try {
      // Capture the annotated canvas as an image
      final boundary = _canvasKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // Wrap the annotated image into a PDF (offline)
      final doc = pw.Document();
      final memImage = pw.MemoryImage(pngBytes);
      doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (_) => pw.Center(child: pw.Image(memImage, fit: pw.BoxFit.contain)),
      ));

      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(await doc.save());

      await Share.shareXFiles([XFile(outPath)], text: 'Edited with AI PDF');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Editor (Offline)'),
        actions: [
          if (_strokes.isNotEmpty)
            IconButton(icon: const Icon(Icons.undo), onPressed: () => setState(() => _strokes.removeLast())),
          if (_pageImage != null)
            IconButton(icon: const Icon(Icons.share), onPressed: _busy ? null : _export, tooltip: 'Export'),
        ],
      ),
      body: _pageImage == null
          ? Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.draw_outlined, size: 72, color: cs.outline),
                const SizedBox(height: 16),
                const Text('Choose a PDF or image to edit', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Choose File'),
                ),
              ]),
            )
          : Column(children: [
              Expanded(
                child: InteractiveViewer(
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: Stack(fit: StackFit.expand, children: [
                      Image.memory(_pageImage!, fit: BoxFit.contain),
                      GestureDetector(
                        onPanStart: (d) => setState(() => _current = [d.localPosition]),
                        onPanUpdate: (d) => setState(() => _current = [..._current, d.localPosition]),
                        onPanEnd: (_) => setState(() {
                          _strokes.add([..._current]);
                          _current = [];
                        }),
                        child: CustomPaint(
                          painter: _AnnotationPainter(_strokes, _current, _color, _stroke),
                          size: Size.infinite,
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              _buildToolbar(cs),
            ]),
    );
  }

  Widget _buildToolbar(ColorScheme cs) => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surface,
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: const Offset(0, -2))],
          ),
          child: Row(children: [
            ...[Colors.red, Colors.blue, Colors.black, Colors.green, Colors.orange].map((c) => GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(color: _color == c ? cs.primary : Colors.grey.shade300, width: _color == c ? 3 : 1),
                    ),
                  ),
                )),
            Expanded(
              child: Slider(value: _stroke, min: 1, max: 15, onChanged: (v) => setState(() => _stroke = v)),
            ),
          ]),
        ),
      );
}

class _AnnotationPainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final List<Offset> current;
  final Color color;
  final double width;
  _AnnotationPainter(this.strokes, this.current, this.color, this.width);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final stroke in [...strokes, current]) {
      if (stroke.length < 2) continue;
      final path = Path()..moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnnotationPainter old) => true;
}
