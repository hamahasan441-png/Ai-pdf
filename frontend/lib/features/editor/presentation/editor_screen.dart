import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';
import '../models/annotation.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/toolbar.dart';
import '../widgets/signature_pad.dart';

class EditorScreen extends ConsumerStatefulWidget {
  final String documentId;
  const EditorScreen({super.key, required this.documentId});
  @override
  ConsumerState<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends ConsumerState<EditorScreen> {
  EditorTool _tool = EditorTool.select;
  Color _color = Colors.black;
  double _stroke = 3;
  int _page = 1, _pages = 1;
  List<PdfAnnotation> _ann = [];
  List<PdfAnnotation> _redoList = [];
  String? _name;
  bool _loading = true, _saving = false, _dirty = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final api = ref.read(apiClientProvider);
      final r = await api.dio.get('${AppConstants.documentsEndpoint}/${widget.documentId}');
      setState(() { _name = r.data['original_filename']; _pages = r.data['page_count'] ?? 1; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  void _add(PdfAnnotation a) => setState(() { _ann.add(a); _redoList.clear(); _dirty = true; });
  void _undo() { if (_ann.isNotEmpty) setState(() { _redoList.add(_ann.removeLast()); _dirty = true; }); }
  void _redo() { if (_redoList.isNotEmpty) setState(() { _ann.add(_redoList.removeLast()); _dirty = true; }); }
  String get _uid => DateTime.now().millisecondsSinceEpoch.toString();

  void _onTool(EditorTool t) {
    if (t == EditorTool.sign) { Navigator.push(context, MaterialPageRoute(fullscreenDialog: true, builder: (_) => SignaturePad(onDone: (pts) => _add(PdfAnnotation(id: 'sig_$_uid', type: AnnotationType.signature, page: _page, position: const Offset(40, 350), size: const Size(240, 80), points: pts))))); return; }
    if (t == EditorTool.stamp) { _stamps(); return; }
    setState(() => _tool = t);
  }

  void _stamps() {
    final list = ['APPROVED', 'REJECTED', 'DRAFT', 'CONFIDENTIAL', 'COPY', 'VOID', 'FINAL', 'URGENT', 'PAID', 'RECEIVED'];
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Add Stamp', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: list.map((s) => ActionChip(label: Text(s, style: TextStyle(fontWeight: FontWeight.w600, color: s == 'APPROVED' || s == 'PAID' ? Colors.green : s == 'REJECTED' || s == 'VOID' ? Colors.red : Colors.blue)), onPressed: () { Navigator.pop(ctx); _add(PdfAnnotation(id: 'st_$_uid', type: AnnotationType.stamp, page: _page, position: const Offset(80, 180), size: const Size(180, 50), text: s, color: s == 'APPROVED' || s == 'PAID' ? Colors.green : s == 'REJECTED' || s == 'VOID' ? Colors.red : Colors.blue)); })).toList()),
    ]))));
  }

  void _tapCanvas(TapDownDetails d) {
    if (_tool == EditorTool.text) { final c = TextEditingController(); showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Add Text'), content: TextField(controller: c, autofocus: true, maxLines: 4, decoration: const InputDecoration(hintText: 'Type...', border: OutlineInputBorder())), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () { if (c.text.isNotEmpty) _add(PdfAnnotation(id: 'tx_$_uid', type: AnnotationType.text, page: _page, position: d.localPosition, text: c.text, color: _color)); Navigator.pop(ctx); }, child: const Text('Add'))])); return; }
    if (_tool == EditorTool.highlight) { _add(PdfAnnotation(id: 'hl_$_uid', type: AnnotationType.highlight, page: _page, position: d.localPosition, size: const Size(180, 22), color: Colors.yellow)); return; }
    if (_tool == EditorTool.shapes) { _add(PdfAnnotation(id: 'sh_$_uid', type: AnnotationType.shape, page: _page, position: d.localPosition, size: const Size(120, 80), color: _color, strokeWidth: _stroke)); return; }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.dio.post('${AppConstants.documentsEndpoint}/${widget.documentId}/annotations', data: {'annotations': _ann.map((a) => a.toJson()).toList()});
      setState(() { _dirty = false; _saving = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved!')));
    } catch (_) { setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('Editor')), body: const Center(child: CircularProgressIndicator()));
    final cs = Theme.of(context).colorScheme;
    final pa = _ann.where((a) => a.page == _page).toList();
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(_name ?? 'Editor', style: const TextStyle(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('Page $_page / $_pages', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ]),
        actions: [
          if (_dirty) TextButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save, size: 20), label: const Text('Save')),
          PopupMenuButton<String>(itemBuilder: (_) => [const PopupMenuItem(value: 'clear', child: Text('Clear Page')), const PopupMenuItem(value: 'all', child: Text('Clear All'))], onSelected: (v) { if (v == 'clear') setState(() { _ann.removeWhere((a) => a.page == _page); _dirty = true; }); if (v == 'all') setState(() { _ann.clear(); _dirty = true; }); }),
        ],
      ),
      body: Column(children: [
        Container(color: cs.surfaceContainerHighest, padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.first_page), onPressed: _page > 1 ? () => setState(() => _page = 1) : null),
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: _page > 1 ? () => setState(() => _page--) : null),
          Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6), decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(8)), child: Text('$_page / $_pages', style: TextStyle(fontWeight: FontWeight.bold, color: cs.onPrimaryContainer))),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: _page < _pages ? () => setState(() => _page++) : null),
          IconButton(icon: const Icon(Icons.last_page), onPressed: _page < _pages ? () => setState(() => _page = _pages) : null),
        ])),
        Expanded(child: GestureDetector(onTapDown: _tapCanvas, child: Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, 4))], border: Border.all(color: Colors.grey.shade200)),
          child: Stack(children: [
            Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.article_outlined, size: 56, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Page $_page', style: TextStyle(color: Colors.grey.shade400, fontSize: 16))])),
            ...pa.map(_renderAnn),
            if (_tool == EditorTool.draw || _tool == EditorTool.eraser) Positioned.fill(child: DrawingCanvas(color: _color, strokeWidth: _stroke, isEraser: _tool == EditorTool.eraser, onComplete: (p) => _add(PdfAnnotation(id: 'dr_$_uid', type: AnnotationType.freehand, page: _page, position: Offset.zero, points: p, color: _color, strokeWidth: _stroke)))),
          ]),
        ))),
        EditorToolbar(active: _tool, color: _color, strokeWidth: _stroke, onTool: _onTool, onColor: (c) => setState(() => _color = c), onStroke: (w) => setState(() => _stroke = w), onUndo: _undo, onRedo: _redo),
      ]),
    );
  }

  Widget _renderAnn(PdfAnnotation a) {
    switch (a.type) {
      case AnnotationType.freehand: return Positioned.fill(child: CustomPaint(painter: _FP(a.points, a.color, a.strokeWidth)));
      case AnnotationType.text: return Positioned(left: a.position.dx, top: a.position.dy, child: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: a.color.withOpacity(0.08), borderRadius: BorderRadius.circular(4), border: Border.all(color: a.color.withOpacity(0.3))), child: Text(a.text ?? '', style: TextStyle(color: a.color, fontSize: 14))));
      case AnnotationType.highlight: return Positioned(left: a.position.dx, top: a.position.dy, child: Container(width: a.size.width, height: a.size.height, color: a.color.withOpacity(0.35)));
      case AnnotationType.stamp: return Positioned(left: a.position.dx, top: a.position.dy, child: Container(width: a.size.width, height: a.size.height, decoration: BoxDecoration(border: Border.all(color: a.color, width: 3), borderRadius: BorderRadius.circular(6)), alignment: Alignment.center, child: Text(a.text ?? '', style: TextStyle(color: a.color, fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 2))));
      case AnnotationType.signature: return Positioned(left: a.position.dx, top: a.position.dy, child: SizedBox(width: a.size.width, height: a.size.height, child: CustomPaint(painter: _FP(a.points, Colors.black, 2.5))));
      case AnnotationType.shape: return Positioned(left: a.position.dx, top: a.position.dy, child: Container(width: a.size.width, height: a.size.height, decoration: BoxDecoration(border: Border.all(color: a.color, width: a.strokeWidth), borderRadius: BorderRadius.circular(4))));
    }
  }
}

class _FP extends CustomPainter {
  final List<Offset> p; final Color c; final double w;
  _FP(this.p, this.c, this.w);
  @override
  void paint(Canvas canvas, Size size) {
    if (p.length < 2) return;
    final paint = Paint()..color = c..strokeWidth = w..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final path = Path()..moveTo(p[0].dx, p[0].dy);
    for (int i = 1; i < p.length; i++) path.lineTo(p[i].dx, p[i].dy);
    canvas.drawPath(path, paint);
  }
  @override
  bool shouldRepaint(covariant _FP old) => true;
}
