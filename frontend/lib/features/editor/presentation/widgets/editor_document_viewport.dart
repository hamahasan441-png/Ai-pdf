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
      child: InteractiveViewer(
        maxScale: 5,
        panEnabled: panEnabled,
        scaleEnabled: scaleEnabled,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return AspectRatio(
                aspectRatio: 1 / 1.414,
                child: RepaintBoundary(child: child),
              );
            },
          ),
        ),
      ),
    );
  }
}
