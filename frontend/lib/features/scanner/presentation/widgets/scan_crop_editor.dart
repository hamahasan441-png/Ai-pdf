import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';
import 'package:ai_pdf/features/scanner/presentation/widgets/scan_edge_overlay_painter.dart';

/// Interactive crop editor: shows the captured image with four draggable corner
/// handles so the user can fine-tune the auto-detected document boundary.
///
/// [corners] are in the original image's pixel space ([imageSize]); the editor
/// maps them into the fitted on-screen rect and back, so dragging is accurate
/// regardless of display scaling (BoxFit.contain).
class ScanCropEditor extends StatefulWidget {
  final Uint8List imageBytes;
  final Size imageSize;
  final DocumentCorners corners;
  final ValueChanged<DocumentCorners> onCornersChanged;

  const ScanCropEditor({
    super.key,
    required this.imageBytes,
    required this.imageSize,
    required this.corners,
    required this.onCornersChanged,
  });

  @override
  State<ScanCropEditor> createState() => _ScanCropEditorState();
}

class _ScanCropEditorState extends State<ScanCropEditor> {
  int? _dragging;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = _fittedRect(
          widget.imageSize,
          Size(constraints.maxWidth, constraints.maxHeight),
        );
        final displayCorners = [
          for (final p in widget.corners.points) _toDisplay(p, fit),
        ];

        return Stack(
          children: [
            Positioned.fromRect(
              rect: fit,
              child: Image.memory(widget.imageBytes, fit: BoxFit.fill),
            ),
            Positioned.fill(
              child: GestureDetector(
                onPanStart: (d) => _onPanStart(d.localPosition, displayCorners),
                onPanUpdate: (d) => _onPanUpdate(d.localPosition, fit),
                onPanEnd: (_) => setState(() => _dragging = null),
                child: CustomPaint(
                  painter: ScanEdgeOverlayPainter(
                    corners: displayCorners,
                    showHandles: true,
                  ),
                ),
              ),
            ),
            // Magnifier while dragging a corner.
            if (_dragging != null)
              _magnifier(displayCorners[_dragging!], fit),
          ],
        );
      },
    );
  }

  void _onPanStart(Offset pos, List<Offset> displayCorners) {
    var nearest = 0;
    var best = double.infinity;
    for (var i = 0; i < 4; i++) {
      final d = (displayCorners[i] - pos).distanceSquared;
      if (d < best) {
        best = d;
        nearest = i;
      }
    }
    // Only grab if reasonably close (within 40 px).
    if (best <= 40 * 40) {
      setState(() => _dragging = nearest);
    }
  }

  void _onPanUpdate(Offset pos, Rect fit) {
    final idx = _dragging;
    if (idx == null) return;
    // Clamp to the image display rect, then convert back to image pixels.
    final clamped = Offset(
      pos.dx.clamp(fit.left, fit.right),
      pos.dy.clamp(fit.top, fit.bottom),
    );
    final imgPoint = _toImage(clamped, fit);
    widget.onCornersChanged(widget.corners.withCorner(idx, imgPoint));
  }

  Widget _magnifier(Offset focus, Rect fit) {
    const size = 100.0;
    // Position the loupe away from the finger.
    final top = focus.dy > 140 ? focus.dy - size - 24 : focus.dy + 24;
    final left = (focus.dx - size / 2).clamp(0.0, fit.right - size);
    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 6)],
          ),
          clipBehavior: Clip.antiAlias,
          child: Transform.scale(
            scale: 2.0,
            child: Transform.translate(
              offset: Offset(
                (fit.center.dx - focus.dx),
                (fit.center.dy - focus.dy),
              ),
              child: Image.memory(widget.imageBytes, fit: BoxFit.fill),
            ),
          ),
        ),
      ),
    );
  }

  /// The rect the image occupies inside [container] under BoxFit.contain.
  Rect _fittedRect(Size image, Size container) {
    if (image.width <= 0 || image.height <= 0) {
      return Offset.zero & container;
    }
    final scale = (container.width / image.width)
        .clamp(0.0, container.height / image.height);
    final w = image.width * scale;
    final h = image.height * scale;
    final left = (container.width - w) / 2;
    final top = (container.height - h) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  Offset _toDisplay(Offset imgPoint, Rect fit) {
    final sx = fit.width / widget.imageSize.width;
    final sy = fit.height / widget.imageSize.height;
    return Offset(fit.left + imgPoint.dx * sx, fit.top + imgPoint.dy * sy);
  }

  Offset _toImage(Offset displayPoint, Rect fit) {
    final sx = widget.imageSize.width / fit.width;
    final sy = widget.imageSize.height / fit.height;
    return Offset(
      (displayPoint.dx - fit.left) * sx,
      (displayPoint.dy - fit.top) * sy,
    );
  }
}
