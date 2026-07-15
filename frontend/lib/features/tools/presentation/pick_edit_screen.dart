import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

import '../widgets/result_sheet.dart';

/// Tools available in the pro editor.
enum EditTool { pan, draw, highlight, text, line, arrow, rect, oval, whiteout, signature, eraser }

/// Shape kinds for the vector shape tools.
enum ShapeType { line, arrow, rect, oval, whiteout }

/// Base type for anything drawn on a page (used for undo/redo ordering).
abstract class _Annotation {}

/// A freehand stroke or highlight (normalized 0..1 coordinates).
class _Stroke extends _Annotation {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool highlight;
  _Stroke(this.points, this.color, this.width, this.highlight);
}

/// A straight line, arrow, or rectangle (normalized coordinates).
class _Shape extends _Annotation {
  final ShapeType type;
  Offset start;
  Offset end;
  final Color color;
  final double width;
  _Shape(this.type, this.start, this.end, this.color, this.width);
}

/// A text box annotation (normalized position).
class _TextBox extends _Annotation {
  Offset pos; // normalized 0..1
  String text;
  Color color;
  double size; // normalized to canvas height
  bool bold;
  _TextBox(this.pos, this.text, this.color, this.size, this.bold);
}

/// Per-page annotation layer with undo + redo history.
class _PageLayer {
  final List<_Annotation> items = [];
  final List<_Annotation> redo = [];

  List<_Stroke> get strokes => items.whereType<_Stroke>().toList();
  List<_Shape> get shapes => items.whereType<_Shape>().toList();
  List<_TextBox> get texts => items.whereType<_TextBox>().toList();
}

/// Professional offline PDF/Image editor.
///
/// Memory-safe: pages are rendered with pdfx at a capped resolution and only
/// a few pages are cached at once. Features: multi-page nav, pinch zoom,
/// freehand draw, highlighter, straight line / arrow / rectangle shapes,
/// movable + editable text boxes (font size, bold, color), signature,
/// eraser, undo/redo, and export to a flattened PDF captured page-by-page so
/// nothing is ever loaded at huge resolution.
class PickEditScreen extends StatefulWidget {
  const PickEditScreen({super.key});
  @override
  State<PickEditScreen> createState() => _PickEditScreenState();
}

class _PickEditScreenState extends State<PickEditScreen> {
  static const int _renderMaxEdge = 1400;
  static const int _maxCachedPages = 3;

  pdfx.PdfDocument? _doc;
  final Map<int, Uint8List> _pageCache = {}; // page index -> jpeg bytes
  final Map<int, _PageLayer> _layers = {};
  int _pageCount = 0;
  int _current = 0;
  bool _loading = false;
  String? _fileName;

  EditTool _tool = EditTool.draw;
  Color _color = Colors.red;
  double _stroke = 3;
  double _textSize = 0.032; // normalized to page height
  bool _bold = false;

  List<Offset> _drawing = [];
  Offset? _shapeStart; // live shape preview (normalized)
  Offset? _shapeEnd;

  // --- Selection state ---
  _Annotation? _selected; // currently selected annotation (for move/resize)
  Offset? _dragOffset; // offset during move
  bool _hasUnsavedChanges = false;

  // --- Saved signatures (persisted across sessions) ---
  static final List<List<Offset>> _savedSignatures = [];

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
        _doc = await pdfx.PdfDocument.openFile(path);
        _pageCount = _doc!.pagesCount;
        await _renderPage(0);
      } else {
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
    _evictFarPages(index);
  }

  /// Bound memory: drop rendered bytes for pages far from [keep].
  /// Annotation layers (tiny) are always retained so edits are never lost.
  void _evictFarPages(int keep) {
    if (_pageCache.length <= _maxCachedPages) return;
    final toRemove = _pageCache.keys
        .where((k) => (k - keep).abs() > 1)
        .toList()
      ..sort((a, b) => (b - keep).abs().compareTo((a - keep).abs()));
    for (final k in toRemove) {
      if (_pageCache.length <= _maxCachedPages) break;
      _pageCache.remove(k);
    }
  }

  Future<void> _goToPage(int index) async {
    if (index < 0 || index >= _pageCount) return;
    setState(() => _loading = true);
    await _renderPage(index);
    setState(() {
      _current = index;
      _loading = false;
    });
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  // ---- Gesture handling (coordinates normalized to canvas) ----

  bool get _isFreehand => _tool == EditTool.draw || _tool == EditTool.highlight;
  bool get _isShape =>
      _tool == EditTool.line || _tool == EditTool.arrow || _tool == EditTool.rect ||
      _tool == EditTool.oval || _tool == EditTool.whiteout;

  void _onPanStart(Offset local, Size canvas) {
    final n = _norm(local, canvas);
    if (_tool == EditTool.pan && _selected != null) {
      // Start moving selected object
      _dragOffset = n;
      return;
    }
    if (_isFreehand) {
      _drawing = [n];
      setState(() {});
    } else if (_isShape) {
      _shapeStart = n;
      _shapeEnd = n;
      setState(() {});
    }
  }

  void _onPanUpdate(Offset local, Size canvas) {
    final n = _norm(local, canvas);
    if (_tool == EditTool.pan && _selected != null && _dragOffset != null) {
      final delta = Offset(n.dx - _dragOffset!.dx, n.dy - _dragOffset!.dy);
      _moveSelected(delta);
      _dragOffset = n;
      return;
    }
    if (_isFreehand) {
      _drawing = [..._drawing, n];
      setState(() {});
    } else if (_isShape && _shapeStart != null) {
      _shapeEnd = n;
      setState(() {});
    }
  }

  void _onPanEnd() {
    _dragOffset = null;
    if (_isFreehand && _drawing.length > 1) {
      _pushItem(_Stroke(
        List.from(_drawing),
        _tool == EditTool.highlight ? _color.withOpacity(0.35) : _color,
        _tool == EditTool.highlight ? 16 : _stroke,
        _tool == EditTool.highlight,
      ));
    } else if (_isShape && _shapeStart != null && _shapeEnd != null) {
      final type = switch (_tool) {
        EditTool.line => ShapeType.line,
        EditTool.arrow => ShapeType.arrow,
        EditTool.oval => ShapeType.oval,
        EditTool.whiteout => ShapeType.whiteout,
        _ => ShapeType.rect,
      };
      if ((_shapeStart! - _shapeEnd!).distance > 0.01) {
        _pushItem(_Shape(type, _shapeStart!, _shapeEnd!, _color, _stroke));
      }
    }
    _drawing = [];
    _shapeStart = null;
    _shapeEnd = null;
    setState(() {});
  }

  void _onTapUp(Offset local, Size canvas) {
    final n = _norm(local, canvas);
    if (_tool == EditTool.text) {
      _editTextBox(_TextBox(n, '', _color, _textSize, _bold), isNew: true);
    } else if (_tool == EditTool.eraser) {
      setState(() {
        if (_layer.items.isNotEmpty) {
          _layer.redo.add(_layer.items.removeLast());
          _hasUnsavedChanges = true;
        }
      });
    } else if (_tool == EditTool.pan) {
      // Tap in pan mode = try to select an object
      setState(() => _selected = _hitTest(n));
    }
  }

  /// Simple hit-test: find the topmost shape/text near the tap point.
  _Annotation? _hitTest(Offset n) {
    // Check text boxes first (on top visually)
    for (final t in _layer.texts.reversed) {
      if ((t.pos - n).distance < 0.06) return t;
    }
    // Check shapes
    for (final s in _layer.shapes.reversed) {
      final center = Offset((s.start.dx + s.end.dx) / 2, (s.start.dy + s.end.dy) / 2);
      if ((center - n).distance < 0.08) return s;
    }
    return null;
  }

  /// Move a selected object by a normalized delta.
  void _moveSelected(Offset deltaNorm) {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      if (sel is _Shape) {
        sel.start = Offset(
          (sel.start.dx + deltaNorm.dx).clamp(0.0, 1.0),
          (sel.start.dy + deltaNorm.dy).clamp(0.0, 1.0),
        );
        sel.end = Offset(
          (sel.end.dx + deltaNorm.dx).clamp(0.0, 1.0),
          (sel.end.dy + deltaNorm.dy).clamp(0.0, 1.0),
        );
      } else if (sel is _TextBox) {
        sel.pos = Offset(
          (sel.pos.dx + deltaNorm.dx).clamp(0.0, 0.98),
          (sel.pos.dy + deltaNorm.dy).clamp(0.0, 0.98),
        );
      }
      _hasUnsavedChanges = true;
    });
  }

  /// Resize a selected shape by adjusting its end point.
  void _resizeSelected(Offset newEndNorm) {
    final sel = _selected;
    if (sel is _Shape) {
      setState(() {
        sel.end = Offset(newEndNorm.dx.clamp(0.0, 1.0), newEndNorm.dy.clamp(0.0, 1.0));
        _hasUnsavedChanges = true;
      });
    }
  }

  void _deleteSelected() {
    if (_selected != null) {
      setState(() {
        _layer.items.remove(_selected);
        _layer.redo.add(_selected!);
        _selected = null;
        _hasUnsavedChanges = true;
      });
    }
  }

  Offset _norm(Offset local, Size canvas) =>
      Offset(local.dx / canvas.width, local.dy / canvas.height);

  /// Add an annotation and reset the redo stack.
  void _pushItem(_Annotation a) {
    _layer.items.add(a);
    _layer.redo.clear();
    _hasUnsavedChanges = true;
  }

  Future<void> _editTextBox(_TextBox box, {bool isNew = false}) async {
    final ctrl = TextEditingController(text: box.text);
    double size = box.size;
    bool bold = box.bold;
    Color color = box.color;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(isNew ? 'Add Text' : 'Edit Text'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Type text...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                const Text('Size'),
                Expanded(
                  child: Slider(
                    value: size,
                    min: 0.015,
                    max: 0.08,
                    onChanged: (v) => setLocal(() => size = v),
                  ),
                ),
                IconButton(
                  tooltip: 'Bold',
                  isSelected: bold,
                  icon: const Icon(Icons.format_bold),
                  onPressed: () => setLocal(() => bold = !bold),
                ),
              ]),
              Row(
                children: [Colors.red, Colors.blue, Colors.black, Colors.green, Colors.orange, Colors.purple]
                    .map((c) => GestureDetector(
                          onTap: () => setLocal(() => color = c),
                          child: Container(
                            width: 28,
                            height: 28,
                            margin: const EdgeInsets.only(right: 8, top: 4),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: color == c ? Colors.blueAccent : Colors.grey.shade400,
                                width: color == c ? 3 : 1,
                              ),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
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
      ),
    );
    if (result == null) return;
    setState(() {
      if (result == '__delete__') {
        _layer.items.remove(box);
      } else if (result.isNotEmpty) {
        box.text = result;
        box.color = color;
        box.size = size;
        box.bold = bold;
        // Remember last-used style for the next text box.
        _textSize = size;
        _bold = bold;
        _color = color;
        if (isNew) _pushItem(box);
      }
    });
  }

  void _undo() {
    setState(() {
      if (_layer.items.isNotEmpty) {
        _layer.redo.add(_layer.items.removeLast());
      }
    });
  }

  void _redoAction() {
    setState(() {
      if (_layer.redo.isNotEmpty) {
        _layer.items.add(_layer.redo.removeLast());
      }
    });
  }

  Future<void> _addSignature() async {
    // Show option: draw new or use saved
    List<Offset>? points;
    if (_savedSignatures.isNotEmpty) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.draw),
                title: const Text('Draw new signature'),
                onTap: () => Navigator.pop(ctx, 'new'),
              ),
              const Divider(height: 1),
              ...List.generate(_savedSignatures.length, (i) => ListTile(
                    leading: const Icon(Icons.gesture),
                    title: Text('Saved signature ${i + 1}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () {
                        _savedSignatures.removeAt(i);
                        Navigator.pop(ctx);
                      },
                    ),
                    onTap: () => Navigator.pop(ctx, 'saved_$i'),
                  )),
            ],
          ),
        ),
      );
      if (choice == null) return;
      if (choice == 'new') {
        points = await _drawSignature();
      } else if (choice.startsWith('saved_')) {
        final idx = int.tryParse(choice.replaceFirst('saved_', ''));
        if (idx != null && idx < _savedSignatures.length) {
          points = _savedSignatures[idx];
        }
      }
    } else {
      points = await _drawSignature();
    }

    if (points != null && points.length > 1) {
      setState(() {
        _pushItem(_Stroke(
          points!.map((p) => Offset(0.1 + p.dx / 900, 0.7 + p.dy / 900)).toList(),
          Colors.black,
          2.5,
          false,
        ));
      });
    }
  }

  Future<List<Offset>?> _drawSignature() async {
    final points = await Navigator.of(context).push<List<Offset>>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _SignaturePad()),
    );
    if (points != null && points.length > 1) {
      // Ask to save for reuse
      final save = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Save this signature?'),
          content: const Text('Saved signatures can be reused instantly next time.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      );
      if (save == true) {
        _savedSignatures.add(List.from(points));
      }
    }
    return points;
  }

  /// Rotate the current page image 90° clockwise. The rotation is applied to
  /// the cached bytes (re-encoded) so it appears immediately and exports correctly.
  Future<void> _rotatePage() async {
    final bytes = _pageCache[_current];
    if (bytes == null) return;
    setState(() => _loading = true);
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final original = frame.image;
      final w = original.height;
      final h = original.width;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      canvas.translate(w.toDouble(), 0);
      canvas.rotate(math.pi / 2);
      canvas.drawImage(original, Offset.zero, Paint());
      original.dispose();
      final picture = recorder.endRecording();
      final rotated = await picture.toImage(w, h);
      final data = await rotated.toByteData(format: ui.ImageByteFormat.png);
      rotated.dispose();
      picture.dispose();
      if (data != null) {
        _pageCache[_current] = data.buffer.asUint8List();
      }
    } catch (e) {
      _showError('Rotate failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---- Export: compose each page off-screen at high resolution ----
  //
  // Pro approach (used by big PDF apps): instead of screenshotting the visible
  // widget (limited to screen resolution and fragile), we re-render each page
  // at a high pixel cap and paint the annotations directly onto an off-screen
  // Canvas. This gives crisp output, is much faster (no per-frame waits), works
  // for pages that aren't on screen, and keeps memory bounded (one page image
  // in flight at a time, disposed immediately).

  static const double _exportMaxEdge = 1800;

  Future<void> _export() async {
    setState(() => _loading = true);
    try {
      final doc = pw.Document();
      var rendered = 0;
      for (var i = 0; i < _pageCount; i++) {
        final png = await _composePagePng(i);
        if (png != null) {
          final image = pw.MemoryImage(png);
          doc.addPage(pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ));
          rendered++;
        }
        // Yield to the event loop so the UI stays responsive on big files.
        await Future<void>.delayed(Duration.zero);
      }

      if (rendered == 0) {
        _showError('Nothing to export');
        return;
      }

      final dir = await getApplicationDocumentsDirectory();
      final outPath = '${dir.path}/edited_${DateTime.now().millisecondsSinceEpoch}.pdf';
      await File(outPath).writeAsBytes(await doc.save());
      if (mounted) {
        setState(() => _loading = false);
        await showResultSheet(context,
            paths: [outPath],
            title: 'Export Complete',
            subtitle: '$rendered page(s) saved');
      }
    } catch (e) {
      _showError('Export failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Render page [index] at high resolution and paint its annotation layer on
  /// top, returning a PNG. Everything is disposed before returning.
  Future<Uint8List?> _composePagePng(int index) async {
    // 1) Obtain the base image bytes for this page (high-res for PDFs).
    Uint8List? baseBytes;
    if (_doc != null) {
      final page = await _doc!.getPage(index + 1);
      try {
        final longEdge = page.width > page.height ? page.width : page.height;
        final scale = longEdge > _exportMaxEdge ? _exportMaxEdge / longEdge : 1.0;
        final img = await page.render(
          width: page.width * scale,
          height: page.height * scale,
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );
        baseBytes = img?.bytes;
      } finally {
        await page.close();
      }
    } else {
      baseBytes = _pageCache[index]; // image file case
    }
    if (baseBytes == null) return null;

    // 2) Decode to a ui.Image so we know the exact pixel dimensions.
    final codec = await ui.instantiateImageCodec(baseBytes);
    final frame = await codec.getNextFrame();
    final base = frame.image;

    try {
      final size = Size(base.width.toDouble(), base.height.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawImage(base, Offset.zero, Paint());
      _AnnDraw.layer(canvas, size, _layers[index]);
      final picture = recorder.endRecording();
      final composed = await picture.toImage(base.width, base.height);
      try {
        final data = await composed.toByteData(format: ui.ImageByteFormat.png);
        return data?.buffer.asUint8List();
      } finally {
        composed.dispose();
        picture.dispose();
      }
    } finally {
      base.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bytes = _pageCache[_current];

    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Unsaved changes'),
            content: const Text('You have unsaved edits. What would you like to do?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save & exit')),
            ],
          ),
        );
        if (action == 'discard' && mounted) {
          setState(() => _hasUnsavedChanges = false);
          Navigator.of(context).pop();
        } else if (action == 'save' && mounted) {
          await _export();
          if (mounted) Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: const Color(0xFF2B2B2B),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_fileName ?? 'PDF Editor',
                style: const TextStyle(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_pageCount > 0)
              Text('Page ${_current + 1} of $_pageCount',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ),
        actions: [
          if (bytes != null) ...[
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
              onPressed: _layer.items.isEmpty ? null : _undo,
            ),
            IconButton(
              icon: const Icon(Icons.redo),
              tooltip: 'Redo',
              onPressed: _layer.redo.isEmpty ? null : _redoAction,
            ),
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export',
              onPressed: _loading ? null : _export,
            ),
          ],
        ],
      ),
      body: bytes == null
          ? _emptyState(cs)
          : Stack(
              children: [
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
    ),
    );
  }

  Widget _buildCanvas(Uint8List bytes) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final canDragText = _tool == EditTool.pan || _tool == EditTool.text;
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
              painter: _AnnPainter(
                _layer.strokes,
                _layer.shapes,
                _drawing,
                _shapeStart,
                _shapeEnd,
                _shapePreviewType(),
                _color,
                _stroke,
                _tool == EditTool.highlight,
              ),
            ),
            // Selection indicator for shapes
            if (_selected is _Shape)
              _buildShapeSelection(size, _selected as _Shape),
            // Text boxes
            ..._layer.texts.map((t) => Positioned(
                  left: t.pos.dx * size.width,
                  top: t.pos.dy * size.height,
                  child: GestureDetector(
                    onTap: () {
                      if (_tool == EditTool.pan) {
                        setState(() => _selected = t);
                      } else {
                        _editTextBox(t);
                      }
                    },
                    onPanUpdate: canDragText
                        ? (d) => setState(() {
                              t.pos = Offset(
                                (t.pos.dx + d.delta.dx / size.width).clamp(0.0, 0.98),
                                (t.pos.dy + d.delta.dy / size.height).clamp(0.0, 0.98),
                              );
                              _hasUnsavedChanges = true;
                            })
                        : null,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        border: _selected == t
                            ? Border.all(color: Colors.blue, width: 2)
                            : null,
                      ),
                      child: Text(
                        t.text,
                        style: TextStyle(
                          color: t.color,
                          fontSize: t.size * size.height,
                          fontWeight: t.bold ? FontWeight.w800 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                )),
            // Selection action bar (appears when something is selected)
            if (_selected != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (_selected is _TextBox) ...[
                      _miniBtn(Icons.edit, 'Edit text', () => _editTextBox(_selected as _TextBox)),
                      const SizedBox(width: 8),
                    ],
                    _miniBtn(Icons.delete_outline, 'Delete', _deleteSelected),
                    const SizedBox(width: 8),
                    _miniBtn(Icons.close, 'Deselect', () => setState(() => _selected = null)),
                  ]),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _miniBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          onTap: onTap,
          child: Icon(icon, size: 20, color: Colors.white),
        ),
      );

  Widget _buildShapeSelection(Size size, _Shape s) {
    final left = math.min(s.start.dx, s.end.dx) * size.width - 4;
    final top = math.min(s.start.dy, s.end.dy) * size.height - 4;
    final w = (s.end.dx - s.start.dx).abs() * size.width + 8;
    final h = (s.end.dy - s.start.dy).abs() * size.height + 8;
    return Positioned(
      left: left,
      top: top,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blue, width: 2),
          ),
        ),
      ),
    );
  }

  ShapeType? _shapePreviewType() {
    switch (_tool) {
      case EditTool.line:
        return ShapeType.line;
      case EditTool.arrow:
        return ShapeType.arrow;
      case EditTool.rect:
        return ShapeType.rect;
      case EditTool.oval:
        return ShapeType.oval;
      case EditTool.whiteout:
        return ShapeType.whiteout;
      default:
        return null;
    }
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
    final showStyle = _tool == EditTool.draw ||
        _tool == EditTool.highlight ||
        _tool == EditTool.text ||
        _isShape;
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
                _toolBtn(Icons.horizontal_rule, 'Line', EditTool.line, cs),
                _toolBtn(Icons.north_east, 'Arrow', EditTool.arrow, cs),
                _toolBtn(Icons.crop_square, 'Box', EditTool.rect, cs),
                _toolBtn(Icons.circle_outlined, 'Oval', EditTool.oval, cs),
                _toolBtn(Icons.format_color_fill, 'Whiteout', EditTool.whiteout, cs),
                _actionBtn(Icons.gesture, 'Sign', _addSignature, cs),
                _toolBtn(Icons.cleaning_services, 'Eraser', EditTool.eraser, cs),
                _actionBtn(Icons.rotate_right, 'Rotate', _rotatePage, cs),
                _actionBtn(Icons.folder_open, 'Open', _pick, cs),
              ]),
            ),
            if (showStyle)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 10, right: 10),
                child: Row(children: [
                  ...[Colors.red, Colors.blue, Colors.black, Colors.green, Colors.orange, Colors.purple]
                      .map((c) => GestureDetector(
                            onTap: () => setState(() => _color = c),
                            child: Container(
                              width: 26,
                              height: 26,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: _color == c ? cs.primary : Colors.grey.shade400,
                                    width: _color == c ? 3 : 1),
                              ),
                            ),
                          )),
                  if (_tool == EditTool.draw || _isShape)
                    Expanded(
                      child: Slider(
                        value: _stroke,
                        min: 1,
                        max: 12,
                        onChanged: (v) => setState(() => _stroke = v),
                      ),
                    ),
                  if (_tool == EditTool.text) ...[
                    Expanded(
                      child: Slider(
                        value: _textSize,
                        min: 0.015,
                        max: 0.08,
                        onChanged: (v) => setState(() => _textSize = v),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Bold',
                      isSelected: _bold,
                      icon: const Icon(Icons.format_bold),
                      onPressed: () => setState(() => _bold = !_bold),
                    ),
                  ],
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
        onTap: () => setState(() => _tool = tool),
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

/// Shared, resolution-independent drawing used by BOTH the on-screen painter
/// and the off-screen export compositor, so the exported PDF looks exactly
/// like what the user sees. Line/arrow/text sizes scale with the canvas height
/// (normalized to a 1000px reference) so a stroke keeps the same relative
/// thickness whether drawn on a phone screen or a 1800px export page.
class _AnnDraw {
  static const double _refHeight = 1000.0;

  static void stroke(Canvas canvas, Size size, List<Offset> pts, Color color, double width) {
    if (pts.length < 2) return;
    final k = size.height / _refHeight;
    final paint = Paint()
      ..color = color
      ..strokeWidth = width * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(pts[0].dx * size.width, pts[0].dy * size.height);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx * size.width, pts[i].dy * size.height);
    }
    canvas.drawPath(path, paint);
  }

  static void shape(Canvas canvas, Size size, ShapeType type, Offset a, Offset b, Color color, double width) {
    final k = size.height / _refHeight;
    final p1 = Offset(a.dx * size.width, a.dy * size.height);
    final p2 = Offset(b.dx * size.width, b.dy * size.height);
    final paint = Paint()
      ..color = color
      ..strokeWidth = width * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    switch (type) {
      case ShapeType.rect:
        canvas.drawRect(Rect.fromPoints(p1, p2), paint);
        break;
      case ShapeType.line:
        canvas.drawLine(p1, p2, paint);
        break;
      case ShapeType.arrow:
        canvas.drawLine(p1, p2, paint);
        _arrowHead(canvas, p1, p2, paint, k);
        break;
      case ShapeType.oval:
        canvas.drawOval(Rect.fromPoints(p1, p2), paint);
        break;
      case ShapeType.whiteout:
        // Filled white rectangle — covers/redacts content underneath.
        final fill = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawRect(Rect.fromPoints(p1, p2), fill);
        // Thin border so you can see it while editing.
        final border = Paint()
          ..color = Colors.grey.shade400
          ..strokeWidth = 1 * k
          ..style = PaintingStyle.stroke;
        canvas.drawRect(Rect.fromPoints(p1, p2), border);
        break;
    }
  }

  static void _arrowHead(Canvas canvas, Offset from, Offset to, Paint paint, double k) {
    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    final headLen = 18.0 * k;
    const headAngle = math.pi / 7;
    final p1 = Offset(
      to.dx - headLen * math.cos(angle - headAngle),
      to.dy - headLen * math.sin(angle - headAngle),
    );
    final p2 = Offset(
      to.dx - headLen * math.cos(angle + headAngle),
      to.dy - headLen * math.sin(angle + headAngle),
    );
    canvas.drawLine(to, p1, paint);
    canvas.drawLine(to, p2, paint);
  }

  static void text(Canvas canvas, Size size, _TextBox t) {
    if (t.text.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: t.text,
        style: TextStyle(
          color: t.color,
          fontSize: t.size * size.height,
          fontWeight: t.bold ? FontWeight.w800 : FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * (1 - t.pos.dx));
    tp.paint(canvas, Offset(t.pos.dx * size.width, t.pos.dy * size.height));
  }

  /// Paint an entire page layer (strokes, shapes, text) onto [canvas].
  static void layer(Canvas canvas, Size size, _PageLayer? layer) {
    if (layer == null) return;
    for (final s in layer.strokes) {
      stroke(canvas, size, s.points, s.color, s.width);
    }
    for (final s in layer.shapes) {
      shape(canvas, size, s.type, s.start, s.end, s.color, s.width);
    }
    for (final t in layer.texts) {
      text(canvas, size, t);
    }
  }
}

/// On-screen painter for freehand strokes, shapes, and live previews.
/// Text boxes are drawn as draggable widgets, so they are not painted here.
class _AnnPainter extends CustomPainter {
  final List<_Stroke> strokes;
  final List<_Shape> shapes;
  final List<Offset> current;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final ShapeType? shapeType;
  final Color curColor;
  final double curWidth;
  final bool curHighlight;

  _AnnPainter(
    this.strokes,
    this.shapes,
    this.current,
    this.shapeStart,
    this.shapeEnd,
    this.shapeType,
    this.curColor,
    this.curWidth,
    this.curHighlight,
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _AnnDraw.stroke(canvas, size, s.points, s.color, s.width);
    }
    for (final s in shapes) {
      _AnnDraw.shape(canvas, size, s.type, s.start, s.end, s.color, s.width);
    }
    if (current.length > 1) {
      _AnnDraw.stroke(canvas, size, current,
          curHighlight ? curColor.withOpacity(0.35) : curColor, curHighlight ? 16 : curWidth);
    }
    if (shapeType != null && shapeStart != null && shapeEnd != null) {
      _AnnDraw.shape(canvas, size, shapeType!, shapeStart!, shapeEnd!, curColor, curWidth);
    }
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
