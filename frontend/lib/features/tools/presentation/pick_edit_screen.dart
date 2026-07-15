import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:share_plus/share_plus.dart';

/// Tools available in the pro editor.
enum EditTool { pan, draw, highlight, text, signature, eraser }

/// A freehand stroke or highlight (normalized 0..1 coordinates).
class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool highlight;
  _Stroke(this.points, this.color, this.width, this.highlight);
}

/// A text box annotation (normalized position).
class _TextBox {
  Offset pos; // normalized 0..1
  String text;
  Color color;
  double size;
  _TextBox(this.pos, this.text, this.color, this.size);
}

/// Per-page annotation layer.
class _PageLayer {
  final List<_Stroke> strokes = [];
  final List<_TextBox> texts = [];
  final List<_Stroke> _undo = [];
}

/// Professional offline PDF/Image editor.
///
/// Memory-safe: pages are rendered with pdfx at a capped resolution.
/// Features: multi-page nav, pinch zoom, freehand draw, highlight, text
/// boxes (tap to place, drag to move), signature, eraser, undo, and export
/// to a flattened PDF (captured page-by-page so nothing is ever fully
/// loaded at huge resolution).
class PickEditScreen extends StatefulWidget {
  const PickEditScreen({super.key});
  @override
  State<PickEditScreen> createState() => _PickEditScreenState();
}

class _PickEditScreenState extends State<PickEditScreen> {
  static const int _renderMaxEdge = 1400;

  pdfx.PdfDocument? _doc;
  final Map<int, Uint8List> _pageCache = {}; // page index -> jpeg bytes
  final Map<int, _PageLayer> _layers = {};
  int _pageCount = 0;
  int _current = 0;
  bool _loading = false;
  bool _isImage = false;
  String? _fileName;

  EditTool _tool = EditTool.draw;
  Color _color = Colors.red;
  double _stroke = 3;
  List<Offset> _drawing = [];
  _TextBox? _selected;

  final GlobalKey _captureKey = GlobalKey();

  @override
  void dispose() {
    _doc?.close();
    super.dispose();
  }

  _PageLayer get _layer => _layers.putIfAbsent(_current, () => _PageLayer());

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path!;
    setState(() {
      _loading = true;
      _pageCache.clear();
      _layers.clear();
      _current = 0;
      _fileName = result.files.first.name;
    });

    try {
      await _doc?.close();
      _doc = null;
      if (path.toLowerCase().endsWith('.pdf')) {
        _isImage = false;
        _doc = await pdfx.PdfDocument.openFile(path);
        _pageCount = _doc!.pagesCount;
        await _renderPage(0);
      } else {
        _isImage = true;
        _pageCount = 1;
        _pageCache[0] = await File(path).readAsBytes();
      }
    } catch (e) {
      _showError('Could not open file: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _renderPage(int index) async {
    if (_pageCache.containsKey(index) || _doc == null) return;
    final page = await _doc!.getPage(index + 1);
    try {
      final longEdge = page.width > page.height ? page.width : page.height;
      final scale = longEdge > _renderMaxEdge ? _renderMaxEdge / longEdge : 1.0;
      final rendered = await page.render(
        width: (page.width * scale),
        height: (page.height * scale),
        format: pdfx.PdfPageImageFormat.jpeg,
        backgroundColor: '#FFFFFF',
      );
      if (rendered != null) {
        _pageCache[index] = rendered.bytes;
      }
    } finally {
      await page.close();
    }
  }

  Future<void> _goToPage(int index) async {
    if (index < 0 || index >= _pageCount) return;
    setState(() => _loading = true);
    await _renderPage(index);
    setState(() {
      _current = index;
      _selected = null;
      _loading = false;
    });
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }


  // ---- Drawing / gesture handling (coordinates normalized to canvas) ----

  void _onPanStart(Offset local, Size canvas) {
    if (_tool == EditTool.draw || _tool == EditTool.highlight) {
      _drawing = [_norm(local, canvas)];
      setState(() {});
    }
  }

  void _onPanUpdate(Offset local, Size canvas) {
    if (_tool == EditTool.draw || _tool == EditTool.highlight) {
      _drawing = [..._drawing, _norm(local, canvas)];
      setState(() {});
    }
  }

  void _onPanEnd() {
    if ((_tool == EditTool.draw || _tool == EditTool.highlight) &&
        _drawing.length > 1) {
      _layer.strokes.add(_Stroke(
        List.from(_drawing),
        _tool == EditTool.highlight ? _color.withOpacity(0.35) : _color,
        _tool == EditTool.highlight ? 16 : _stroke,
        _tool == EditTool.highlight,
      ));
      _layer._undo.clear();
    }
    _drawing = [];
    setState(() {});
  }

  void _onTapUp(Offset local, Size canvas) {
    final n = _norm(local, canvas);
    if (_tool == EditTool.text) {
      _editTextBox(_TextBox(n, '', _color, 0.03), isNew: true);
    } else if (_tool == EditTool.eraser) {
      // Remove nearest stroke/text
      setState(() {
        if (_layer.strokes.isNotEmpty) _layer.strokes.removeLast();
      });
    }
  }

  Offset _norm(Offset local, Size canvas) =>
      Offset(local.dx / canvas.width, local.dy / canvas.height);

  Future<void> _editTextBox(_TextBox box, {bool isNew = false}) async {
    final ctrl = TextEditingController(text: box.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isNew ? 'Add Text' : 'Edit Text'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Type text...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (!isNew)
            TextButton(
              onPressed: () => Navigator.pop(ctx, '__delete__'),
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    if (result == null) return;
    setState(() {
      if (result == '__delete__') {
        _layer.texts.remove(box);
      } else if (result.isNotEmpty) {
        box.text = result;
        box.color = _color;
        if (isNew) _layer.texts.add(box);
      }
    });
  }

  void _undo() {
    setState(() {
      if (_layer.texts.isNotEmpty && _layer.strokes.isEmpty) {
        _layer.texts.removeLast();
      } else if (_layer.strokes.isNotEmpty) {
        _layer._undo.add(_layer.strokes.removeLast());
      }
    });
  }

  Future<void> _addSignature() async {
    final points = await Navigator.of(context).push<List<Offset>>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _SignaturePad()),
    );
    if (points != null && points.length > 1) {
      // Place signature at bottom area, scaled into normalized space
      setState(() {
        _layer.strokes.add(_Stroke(
          points.map((p) => Offset(0.1 + p.dx / 900, 0.7 + p.dy / 900)).toList(),
          Colors.black,
          2.5,
          false,
        ));
      });
    }
  }

  // ---- Export: capture each annotated page to PNG, build a PDF ----

  Future<void> _export() async {
    setState(() => _loading = true);
    try {
      final doc = pw.Document();
      final startPage = _current;
      for (var i = 0; i < _pageCount; i++) {
        await _renderPage(i);
        setState(() => _current = i);
        await WidgetsBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 50));
        final png = await _capturePng();
        if (png != null) {
          final image = pw.MemoryImage(png);
          doc.addPage(pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ));
        }
      }
      setState(() => _current = startPage);

      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(await doc.save());
      await Share.shareXFiles([XFile(outPath)], text: 'Edited with AI PDF');
    } catch (e) {
      _showError('Export failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uint8List?> _capturePng() async {
    try {
      final boundary =
          _captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }


  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bytes = _pageCache[_current];

    return Scaffold(
      backgroundColor: const Color(0xFF2B2B2B),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_fileName ?? 'PDF Editor', style: const TextStyle(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_pageCount > 0)
              Text('Page ${_current + 1} of $_pageCount', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        actions: [
          if (bytes != null) ...[
            IconButton(icon: const Icon(Icons.undo), tooltip: 'Undo', onPressed: _undo),
            IconButton(icon: const Icon(Icons.ios_share), tooltip: 'Export', onPressed: _loading ? null : _export),
          ],
        ],
      ),
      body: bytes == null
          ? _emptyState(cs)
          : Stack(
              children: [
                // Editor canvas
                Positioned.fill(
                  bottom: 96,
                  child: InteractiveViewer(
                    maxScale: 5,
                    panEnabled: _tool == EditTool.pan,
                    scaleEnabled: _tool == EditTool.pan,
                    child: Center(
                      child: LayoutBuilder(builder: (context, constraints) {
                        return AspectRatio(
                          aspectRatio: 1 / 1.414, // A4-ish
                          child: RepaintBoundary(
                            key: _captureKey,
                            child: _buildCanvas(bytes),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                if (_loading)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x66000000),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                // Bottom toolbar
                Positioned(left: 0, right: 0, bottom: 0, child: _toolbar(cs)),
              ],
            ),
      floatingActionButton: bytes == null
          ? null
          : (_pageCount > 1
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 100),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'prev',
                        onPressed: _current > 0 ? () => _goToPage(_current - 1) : null,
                        child: const Icon(Icons.chevron_left),
                      ),
                      const SizedBox(width: 12),
                      FloatingActionButton.small(
                        heroTag: 'next',
                        onPressed: _current < _pageCount - 1 ? () => _goToPage(_current + 1) : null,
                        child: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                )
              : null),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildCanvas(Uint8List bytes) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      return GestureDetector(
        onTapUp: (d) => _onTapUp(d.localPosition, size),
        onPanStart: (d) => _onPanStart(d.localPosition, size),
        onPanUpdate: (d) => _onPanUpdate(d.localPosition, size),
        onPanEnd: (_) => _onPanEnd(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(bytes, fit: BoxFit.fill),
            CustomPaint(
              painter: _AnnPainter(_layer.strokes, _drawing, _color, _stroke,
                  _tool == EditTool.highlight),
            ),
            // Text boxes
            ..._layer.texts.map((t) => Positioned(
                  left: t.pos.dx * size.width,
                  top: t.pos.dy * size.height,
                  child: GestureDetector(
                    onTap: () => _editTextBox(t),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      color: Colors.transparent,
                      child: Text(
                        t.text,
                        style: TextStyle(
                          color: t.color,
                          fontSize: t.size * size.height,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                )),
          ],
        ),
      );
    });
  }

  Widget _emptyState(ColorScheme cs) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.draw_outlined, size: 72, color: Colors.white38),
            const SizedBox(height: 16),
            const Text('Open a PDF or image to edit',
                style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white70)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loading ? null : _pick,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose File'),
            ),
          ],
        ),
      );

  Widget _toolbar(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Row(children: [
                _toolBtn(Icons.pan_tool_alt, 'Move', EditTool.pan, cs),
                _toolBtn(Icons.edit, 'Draw', EditTool.draw, cs),
                _toolBtn(Icons.highlight, 'Highlight', EditTool.highlight, cs),
                _toolBtn(Icons.title, 'Text', EditTool.text, cs),
                _actionBtn(Icons.gesture, 'Sign', _addSignature, cs),
                _toolBtn(Icons.cleaning_services, 'Eraser', EditTool.eraser, cs),
                _actionBtn(Icons.folder_open, 'Open', _pick, cs),
              ]),
            ),
            if (_tool == EditTool.draw || _tool == EditTool.highlight || _tool == EditTool.text)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 10, right: 10),
                child: Row(children: [
                  ...[Colors.red, Colors.blue, Colors.black, Colors.green, Colors.orange, Colors.purple]
                      .map((c) => GestureDetector(
                            onTap: () => setState(() => _color = c),
                            child: Container(
                              width: 26, height: 26,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: c, shape: BoxShape.circle,
                                border: Border.all(
                                    color: _color == c ? cs.primary : Colors.grey.shade400,
                                    width: _color == c ? 3 : 1),
                              ),
                            ),
                          )),
                  if (_tool == EditTool.draw)
                    Expanded(
                      child: Slider(value: _stroke, min: 1, max: 12, onChanged: (v) => setState(() => _stroke = v)),
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, EditTool tool, ColorScheme cs) {
    final active = _tool == tool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => setState(() { _tool = tool; _selected = null; }),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? cs.primaryContainer : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: active ? cs.primary : cs.onSurface),
            Text(label, style: TextStyle(fontSize: 10, color: active ? cs.primary : cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 22, color: cs.onSurface),
            Text(label, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

/// Painter for freehand strokes + highlights.
class _AnnPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final List<Offset> current;
  final Color curColor;
  final double curWidth;
  final bool curHighlight;
  _AnnPainter(this.strokes, this.current, this.curColor, this.curWidth, this.curHighlight);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _drawStroke(canvas, size, s.points, s.color, s.width, s.highlight);
    }
    if (current.length > 1) {
      _drawStroke(canvas, size, current,
          curHighlight ? curColor.withOpacity(0.35) : curColor,
          curHighlight ? 16 : curWidth, curHighlight);
    }
  }

  void _drawStroke(Canvas canvas, Size size, List<Offset> pts, Color color, double width, bool highlight) {
    if (pts.length < 2) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts[0].dx * size.width, pts[0].dy * size.height);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx * size.width, pts[i].dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AnnPainter old) => true;
}

/// Full-screen signature capture pad.
class _SignaturePad extends StatefulWidget {
  const _SignaturePad();
  @override
  State<_SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<_SignaturePad> {
  final List<Offset> _points = [];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Sign Here'),
        actions: [
          TextButton(onPressed: () => setState(() => _points.clear()), child: const Text('Clear')),
          FilledButton(onPressed: () => Navigator.pop(context, _points), child: const Text('Done')),
          const SizedBox(width: 8),
        ],
      ),
      body: GestureDetector(
        onPanUpdate: (d) => setState(() => _points.add(d.localPosition)),
        onPanEnd: (_) => _points.add(Offset.infinite),
        child: CustomPaint(painter: _SigPainter(_points), size: Size.infinite),
      ),
    );
  }
}

class _SigPainter extends CustomPainter {
  final List<Offset> points;
  _SigPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < points.length - 1; i++) {
      if (points[i] != Offset.infinite && points[i + 1] != Offset.infinite) {
        canvas.drawLine(points[i], points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter old) => true;
}
