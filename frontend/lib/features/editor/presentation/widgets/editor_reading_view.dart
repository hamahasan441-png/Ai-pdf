import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/image_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/data/rtl_text_renderer.dart';
import 'package:ai_pdf/features/editor/data/stamp_annotation_renderer.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/presentation/widgets/editor_canvas_painter.dart';

/// All pages in one vertical scroll, for reading. Each page shows its marks
/// and form fields read-only. Pages are rendered as they come into view
/// ([requestPage]); tapping a page calls [onOpenPage] to edit it.
class EditorReadingView extends StatefulWidget {
  final int pageCount;
  final int initialPage;
  final double Function(int page) aspectOf;
  final Uint8List? Function(int page) bytesOf;
  final void Function(int page) requestPage;
  final PageLayer? Function(int page) layerOf;
  final Widget? Function(int page) formLayerOf;
  final ImageAnnotationRenderer imageRenderer;
  final StampAnnotationRenderer stampRenderer;
  final ColorFilter? viewFilter;
  final ValueChanged<int> onOpenPage;
  final int revision;

  const EditorReadingView({
    super.key,
    required this.pageCount,
    required this.initialPage,
    required this.aspectOf,
    required this.bytesOf,
    required this.requestPage,
    required this.layerOf,
    required this.formLayerOf,
    required this.imageRenderer,
    required this.stampRenderer,
    required this.onOpenPage,
    this.viewFilter,
    this.revision = 0,
  });

  static const double gap = 12;
  static const double margin = 12;

  /// Scroll offset of the top of [page] for pages [width] wide.
  static double offsetOf(int page, double width, double Function(int) aspectOf) {
    var y = gap / 2;
    for (var i = 0; i < page; i++) {
      y += width / aspectOf(i) + gap;
    }
    return y;
  }

  @override
  State<EditorReadingView> createState() => _EditorReadingViewState();
}

class _EditorReadingViewState extends State<EditorReadingView> {
  ScrollController? _scroll;
  double? _width;

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      bottom: 96,
      child: LayoutBuilder(builder: (context, c) {
        final width = (c.maxWidth - 2 * EditorReadingView.margin).clamp(1.0, double.infinity);
        if (_scroll == null || _width != width) {
          // Open where the editor was.
          final start = EditorReadingView.offsetOf(widget.initialPage, width, widget.aspectOf);
          _scroll?.dispose();
          _scroll = ScrollController(initialScrollOffset: start);
          _width = width;
        }
        return ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(vertical: EditorReadingView.gap / 2),
          itemCount: widget.pageCount,
          // Page heights are known, so the list can place the start page
          // and jump far without laying out every page before it.
          itemExtentBuilder: (i, _) => width / widget.aspectOf(i) + EditorReadingView.gap,
          // Render one screen ahead so scrolling does not show blank pages.
          cacheExtent: c.maxHeight,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: EditorReadingView.margin,
              vertical: EditorReadingView.gap / 2,
            ),
            child: _page(context, i, width),
          ),
        );
      }),
    );
  }

  Widget _page(BuildContext context, int i, double width) {
    final bytes = widget.bytesOf(i);
    if (bytes == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.requestPage(i);
      });
    }
    final layer = widget.layerOf(i);
    final form = widget.formLayerOf(i);
    Widget page = Stack(
      fit: StackFit.expand,
      children: [
        if (bytes != null)
          Image.memory(
            bytes,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round().clamp(64, 2400),
          )
        else
          const ColoredBox(color: Colors.white),
        if (form != null) form,
        if (layer != null)
          CustomPaint(
            painter: EditorCanvasPainter(
              layer.strokes,
              layer.shapes,
              layer.images,
              layer.stamps,
              widget.imageRenderer,
              widget.stampRenderer,
              const [],
              null,
              null,
              null,
              Colors.black,
              1,
              false,
              markups: layer.markups,
              revision: widget.revision,
            ),
            foregroundPainter: _TextPainter(layer),
          ),
        if (bytes == null) const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ],
    );
    if (widget.viewFilter != null) page = ColorFiltered(colorFilter: widget.viewFilter!, child: page);
    return Semantics(
      button: true,
      label: '${i + 1} / ${widget.pageCount}',
      child: GestureDetector(
        onTap: () => widget.onOpenPage(i),
        child: SizedBox(
          width: width,
          height: width / widget.aspectOf(i),
          child: DecoratedBox(
            decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x55000000), blurRadius: 4)]),
            child: page,
          ),
        ),
      ),
    );
  }
}

/// Text marks, drawn the way the export draws them.
class _TextPainter extends CustomPainter {
  final PageLayer layer;
  _TextPainter(this.layer);

  static const _text = RtlTextRenderer();

  @override
  void paint(Canvas canvas, Size size) {
    for (final t in layer.texts) {
      if (t.visible) _text.paint(canvas, size, t);
    }
  }

  @override
  bool shouldRepaint(_TextPainter old) => true;
}
