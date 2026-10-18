import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/services/page_fit.dart';

/// Wraps the editor canvas in a pannable/zoomable viewport.
///
/// ### Why StatefulWidget + TransformationController
/// `InteractiveViewer` without a persistent `TransformationController`
/// **resets its transform on every parent rebuild**. The editor screen triggers
/// rebuilds frequently (field detection, tool changes, selection) — each one
/// was causing the canvas to momentarily appear then collapse back, creating
/// the "shows for 0.5s then disappears" symptom.
///
/// ### Why LayoutBuilder is OUTSIDE InteractiveViewer
/// `InteractiveViewer` (with default `constrained: true`) passes the parent's
/// constraints to its child. But when `constrained: false` is used (or the
/// child has no intrinsic size), `AspectRatio` receives infinite constraints
/// and lays out at 0×0. By computing a concrete size from the available space
/// and wrapping the child in a `SizedBox`, the layout is deterministic
/// regardless of `InteractiveViewer`'s constraint mode.
class EditorDocumentViewport extends StatefulWidget {
  final bool panEnabled;
  final bool scaleEnabled;
  final double pageAspect;
  final TransformationController? transformationController;

  /// Changes only how the page looks on screen (reading mode).
  final ColorFilter? viewFilter;
  final Widget child;

  const EditorDocumentViewport({
    super.key,
    required this.panEnabled,
    required this.scaleEnabled,
    this.pageAspect = PageFit.a4PortraitAspect,
    this.transformationController,
    this.viewFilter,
    required this.child,
  });

  @override
  State<EditorDocumentViewport> createState() => _EditorDocumentViewportState();
}

class _EditorDocumentViewportState extends State<EditorDocumentViewport>
    with SingleTickerProviderStateMixin {
  /// Zoom a double-tap goes to from the fitted page.
  static const double doubleTapScale = 2.5;

  TransformationController? _owned;
  late final AnimationController _zoomAnim;
  Animation<Matrix4>? _zoomTween;
  Offset? _doubleTapAt;

  TransformationController get _controller =>
      widget.transformationController ?? _owned!;

  @override
  void initState() {
    super.initState();
    _zoomAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))
      ..addListener(_onZoomTick);
    if (widget.transformationController == null) {
      _owned = TransformationController();
    }
  }

  @override
  void dispose() {
    _zoomAnim.dispose();
    _owned?.dispose();
    super.dispose();
  }

  void _onZoomTick() {
    final t = _zoomTween;
    if (t != null) _controller.value = t.value;
  }

  /// Double-tap: zoom in around the tapped point, or back to the whole page
  /// when already zoomed in.
  void _onDoubleTap() {
    final at = _doubleTapAt;
    if (at == null) return;
    final current = _controller.value;
    final Matrix4 target;
    if (current.getMaxScaleOnAxis() > 1.01) {
      target = Matrix4.identity();
    } else {
      final scene = _controller.toScene(at);
      const s = doubleTapScale;
      target = Matrix4.identity()
        ..translate(-scene.dx * (s - 1), -scene.dy * (s - 1))
        ..scale(s);
    }
    _zoomTween = Matrix4Tween(begin: current, end: target)
        .animate(CurvedAnimation(parent: _zoomAnim, curve: Curves.easeOutCubic));
    _zoomAnim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      bottom: 96,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Compute a concrete page size from finite parent constraints.
          // LayoutBuilder here gets FINITE constraints from Positioned.fill
          // (which fills the Stack minus the toolbar). We pass a concrete Size
          // via SizedBox so InteractiveViewer's child has a FINITE intrinsic
          // size. Without this, AspectRatio/Image.memory lay out at 0×0.
          final fitted = PageFit.box(
            maxWidth: constraints.maxWidth,
            maxHeight: constraints.maxHeight,
            aspect: widget.pageAspect,
          );

          final viewer = InteractiveViewer(
            transformationController: _controller,
            maxScale: 5,
            panEnabled: widget.panEnabled,
            scaleEnabled: widget.scaleEnabled,
            child: Center(
              child: SizedBox(
                width: fitted.width,
                height: fitted.height,
                child: RepaintBoundary(
                  child: widget.viewFilter == null
                      ? widget.child
                      : ColorFiltered(colorFilter: widget.viewFilter!, child: widget.child),
                ),
              ),
            ),
          );
          // Only while panning: a double-tap recognizer delays every single
          // tap, which would make drawing and placing text feel slow.
          if (!widget.panEnabled || !widget.scaleEnabled) return viewer;
          return GestureDetector(
            onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
            onDoubleTap: _onDoubleTap,
            child: viewer,
          );
        },
      ),
    );
  }
}
