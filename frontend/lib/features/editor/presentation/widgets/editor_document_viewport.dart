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
  final Widget child;

  const EditorDocumentViewport({
    super.key,
    required this.panEnabled,
    required this.scaleEnabled,
    this.pageAspect = PageFit.a4PortraitAspect,
    required this.child,
  });

  @override
  State<EditorDocumentViewport> createState() => _EditorDocumentViewportState();
}

class _EditorDocumentViewportState extends State<EditorDocumentViewport> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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

          return InteractiveViewer(
            transformationController: _controller,
            maxScale: 5,
            panEnabled: widget.panEnabled,
            scaleEnabled: widget.scaleEnabled,
            child: Center(
              child: SizedBox(
                width: fitted.width,
                height: fitted.height,
                child: RepaintBoundary(child: widget.child),
              ),
            ),
          );
        },
      ),
    );
  }
}
