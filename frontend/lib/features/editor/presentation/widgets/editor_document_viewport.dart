import 'package:flutter/material.dart';

class EditorDocumentViewport extends StatelessWidget {
  final bool panEnabled;
  final bool scaleEnabled;
  final Widget child;

  const EditorDocumentViewport({
    super.key,
    required this.panEnabled,
    required this.scaleEnabled,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      bottom: 96,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Calculate the page size from the available space, maintaining A4
          // portrait aspect ratio (1:1.414). LayoutBuilder here gets FINITE
          // constraints from Positioned.fill (which fills the Stack minus the
          // toolbar). We compute a concrete Size and pass it to the child via
          // SizedBox so that InteractiveViewer's child has a FINITE intrinsic
          // size. Without this, InteractiveViewer gives its child unbounded
          // constraints → AspectRatio/Image.memory lay out at 0×0 → blank canvas.
          final maxW = constraints.maxWidth;
          final maxH = constraints.maxHeight;
          const aspectRatio = 1 / 1.414; // A4 portrait

          double pageW, pageH;
          if (maxW / maxH > aspectRatio) {
            // Height-limited
            pageH = maxH;
            pageW = maxH * aspectRatio;
          } else {
            // Width-limited
            pageW = maxW;
            pageH = maxW / aspectRatio;
          }

          return InteractiveViewer(
            maxScale: 5,
            panEnabled: panEnabled,
            scaleEnabled: scaleEnabled,
            child: Center(
              child: SizedBox(
                width: pageW,
                height: pageH,
                child: RepaintBoundary(child: child),
              ),
            ),
          );
        },
      ),
    );
  }
}
