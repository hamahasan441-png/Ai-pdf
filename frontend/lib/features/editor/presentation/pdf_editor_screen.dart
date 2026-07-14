import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_client.dart';
import '../models/annotation.dart';
import '../widgets/drawing_canvas.dart';
import '../widgets/editor_toolbar.dart';
import '../widgets/signature_pad.dart';

class PdfEditorScreen extends ConsumerStatefulWidget {
  final String documentId;
  const PdfEditorScreen({super.key, required this.documentId});
  @override
  ConsumerState<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends ConsumerState<PdfEditorScreen> {
  EditorTool _activeTool = EditorTool.select;
  Color _activeColor = Colors.black;
  double _strokeWidth = 3.0;
  int _currentPage = 1;
  int _totalPages = 1;
  List<PdfAnnotation> _annotations = [];
  List<PdfAnnotation> _undoStack = [];
  String? _documentName;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasChanges = false;

  @override
  void initState() { super.initState(); _loadDocument(); }

  Future<void> _loadDocument() async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.dio.get('${AppConstants.documentsEndpoint}/${widget.documentId}');
      setState(() { _documentName = response.data['original_filename'] ?? 'Document'; _totalPages = response.data['page_count'] ?? 1; _isLoading = false; });
    } catch (e) { setState(() => _isLoading = false); }
  }

  void _addAnnotation(PdfAnnotation a) { setState(() { _annotations.add(a); _undoStack.clear(); _hasChanges = true; }); }
  void _undo() { if (_annotations.isEmpty) return; setState(() { _undoStack.add(_annotations.removeLast()); _hasChanges = true; }); }
  void _redo() { if (_undoStack.isEmpty) return; setState(() { _annotations.add(_undoStack.removeLast()); _hasChanges = true; }); }

  void _onToolChanged(EditorTool tool) {
    if (tool == EditorTool.signature) { _showSignaturePad(); return; }
    if (tool == EditorTool.stamp) { _showStampDialog(); return; }
    setState(() => _activeTool = tool);
  }

  void _showSignaturePad() {
    Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => SignaturePad(onSave: (points) {
      _addAnnotation(PdfAnnotation(id: 'sig_${DateTime.now().millisecondsSinceEpoch}', type: AnnotationType.signature, pageNumber: _currentPage, position: const Offset(50, 400), size: const Size(250, 80), points: points, color: Colors.black));
    })));
  }

  void _showStampDialog() {
    final stamps = ['APPROVED', 'REJECTED', 'DRAFT', 'CONFIDENTIAL', 'COPY', 'VOID', 'FINAL', 'URGENT'];
    showModalBottomSheet(context: context, builder: (ctx) => SafeArea(child: Padding(padding: const EdgeInsets.all(16), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Add Stamp', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: stamps.map((s) => ActionChip(label: Text(s), onPressed: () { Navigator.pop(ctx); _addAnnotation(PdfAnnotation(id: 'stamp_${DateTime.now().millisecondsSinceEpoch}', type: AnnotationType.stamp, pageNumber: _currentPage, position: const Offset(100, 200), size: const Size(200, 60), text: s, color: s == 'APPROVED' ? Colors.green : s == 'REJECTED' ? Colors.red : Colors.blue)); })).toList()),
    ]))));
  }

  void _onCanvasTap(TapDownDetails details) {
    if (_activeTool == EditorTool.text) _showTextInput(details.localPosition);
    else if (_activeTool == EditorTool.highlight) _addAnnotation(PdfAnnotation(id: 'hl_${DateTime.now().millisecondsSinceEpoch}', type: AnnotationType.highlight, pageNumber: _currentPage, position: details.localPosition, size: const Size(200, 24), color: Colors.yellow));
  }

  void _showTextInput(Offset pos) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Add Text'), content: TextField(controller: ctrl, autofocus: true, maxLines: 3, decoration: const InputDecoration(hintText: 'Type text...')),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () { if (ctrl.text.isNotEmpty) _addAnnotation(PdfAnnotation(id: 'txt_${DateTime.now().millisecondsSinceEpoch}', type: AnnotationType.text, pageNumber: _currentPage, position: pos, text: ctrl.text, color: _activeColor)); Navigator.pop(ctx); }, child: const Text('Add'))],
    ));
  }

  Future<void> _saveAnnotations() async {
    setState(() => _isSaving = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.dio.post('${AppConstants.documentsEndpoint}/${widget.documentId}/annotations', data: {'annotations': _annotations.map((a) => a.toJson()).toList()});
      setState(() { _hasChanges = false; _isSaving = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Annotations saved!')));
    } catch (e) { setState(() => _isSaving = false); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'))); }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return Scaffold(appBar: AppBar(title: const Text('PDF Editor')), body: const Center(child: CircularProgressIndicator()));
    final pageAnnotations = _annotations.where((a) => a.pageNumber == _currentPage).toList();

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_documentName ?? 'Editor', style: const TextStyle(fontSize: 16)),
          Text('Page $_currentPage / $_totalPages', style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
        actions: [
          if (_hasChanges) TextButton.icon(onPressed: _isSaving ? null : _saveAnnotations, icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save), label: const Text('Save')),
          PopupMenuButton<String>(itemBuilder: (_) => [const PopupMenuItem(value: 'export', child: Text('Export PDF')), const PopupMenuItem(value: 'clear', child: Text('Clear All'))], onSelected: (v) { if (v == 'clear') setState(() { _undoStack = List.from(_annotations); _annotations.clear(); _hasChanges = true; }); }),
        ],
      ),
      body: Column(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Theme.of(context).colorScheme.surfaceContainerHighest, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: _currentPage > 1 ? () => setState(() => _currentPage--) : null),
          Text('Page $_currentPage of $_totalPages', style: const TextStyle(fontWeight: FontWeight.w500)),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: _currentPage < _totalPages ? () => setState(() => _currentPage++) : null),
        ])),
        Expanded(child: GestureDetector(onTapDown: _onCanvasTap, child: Stack(children: [
          Container(margin: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4))], border: Border.all(color: Colors.grey.shade200)), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Page $_currentPage', style: TextStyle(fontSize: 18, color: Colors.grey.shade400))]))),
          Positioned.fill(child: Padding(padding: const EdgeInsets.all(16), child: AnnotationOverlay(annotations: pageAnnotations))),
          if (_activeTool == EditorTool.freehand || _activeTool == EditorTool.eraser)
            Positioned.fill(child: Padding(padding: const EdgeInsets.all(16), child: DrawingCanvas(color: _activeColor, strokeWidth: _strokeWidth, isEraser: _activeTool == EditorTool.eraser, onDrawingComplete: (pts) => _addAnnotation(PdfAnnotation(id: 'draw_${DateTime.now().millisecondsSinceEpoch}', type: AnnotationType.freehand, pageNumber: _currentPage, position: Offset.zero, points: pts, color: _activeColor, strokeWidth: _strokeWidth))))),
        ]))),
        EditorToolbar(activeTool: _activeTool, activeColor: _activeColor, strokeWidth: _strokeWidth, onToolChanged: _onToolChanged, onColorChanged: (c) => setState(() => _activeColor = c), onStrokeWidthChanged: (w) => setState(() => _strokeWidth = w), onUndo: _undo, onRedo: _redo, onSave: _saveAnnotations),
      ]),
    );
  }
}
