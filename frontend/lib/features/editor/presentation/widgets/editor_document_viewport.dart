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

  /// Put on the InteractiveViewer, so callers can map screen points into the
  /// space its transformation works in (to bring a spot into view).
  final GlobalKey? viewerKey;

  /// Changes only how the page looks on screen (reading mode).
  final ColorFilter? viewFilter;

  /// A horizontal fling on the unzoomed page: 1 for the next page, -1 for
  /// the previous one. Null turns page swiping off.
  final ValueChanged<int>? onSwipePage;

  /// A tap beside the page (not on it).
  final VoidCallback? onBackgroundTap;
  final Widget child;

  const EditorDocumentViewport({
    super.key,
    required this.panEnabled,
    required this.scaleEnabled,
    this.pageAspect = PageFit.a4PortraitAspect,
    this.transformationController,
    this.viewerKey,
    this.viewFilter,
    this.onSwipePage,
    this.onBackgroundTap,
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

  /// Turns the page on a quick sideways fling, only while the whole page is
  /// shown (zoomed in, a drag pans the page instead).
  void _onInteractionEnd(ScaleEndDetails d) {
    final swipe = widget.onSwipePage;
    if (swipe == null || d.pointerCount > 1) return;
    if (_controller.value.getMaxScaleOnAxis() > 1.02) return;
    final v = d.velocity.pixelsPerSecond;
    if (v.dx.abs() < 600 || v.dx.abs() < v.dy.abs() * 1.5) return;
    swipe(v.dx < 0 ? 1 : -1);
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
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
            key: widget.viewerKey,
            transformationController: _controller,
            maxScale: 5,
            panEnabled: widget.panEnabled,
            scaleEnabled: widget.scaleEnabled,
            onInteractionEnd: _onInteractionEnd,
            child: Center(
              child: SizedBox(
                width: fitted.width,
                height: fitted.height,
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      boxShadow: [BoxShadow(color: Color(0x2E1B2130), blurRadius: 22, offset: Offset(0, 10))],
                    ),
                    child: widget.viewFilter == null
                        ? widget.child
                        : ColorFiltered(colorFilter: widget.viewFilter!, child: widget.child),
                  ),
                ),
              ),
            ),
          );
          // Only while panning: a double-tap recognizer delays every single
          // tap, which would make drawing and placing text feel slow.
          // A tap on the page itself is the canvas's (its recognizer is
          // deeper, so it wins); only taps beside the page reach this one.
          if (!widget.panEnabled || !widget.scaleEnabled) {
            if (widget.onBackgroundTap == null) return viewer;
            return GestureDetector(onTap: widget.onBackgroundTap, child: viewer);
          }
          return GestureDetector(
            onTap: widget.onBackgroundTap,
            onDoubleTapDown: (d) => _doubleTapAt = d.localPosition,
            onDoubleTap: _onDoubleTap,
            child: viewer,
          );
        },
      ),
    );
  }
}
