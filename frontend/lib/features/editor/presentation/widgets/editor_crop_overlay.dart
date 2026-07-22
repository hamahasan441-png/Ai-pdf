import 'dart:ui' show Rect;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_crop_controller.dart';

/// Overlay showing the crop rect with draggable handles and dimmed outside
/// area (Phase 42).
class EditorCropOverlay extends StatelessWidget {
  final EditorCropState cropState;
  final Size pageSize;
  final void Function(CropHandle) onHandleDragStart;
  final ValueChanged<Offset> onHandleDragUpdate;
  final VoidCallback onHandleDragEnd;

  const EditorCropOverlay({
    super.key,
    required this.cropState,
    required this.pageSize,
    required this.onHandleDragStart,
    required this.onHandleDragUpdate,
    required this.onHandleDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: pageSize,
      painter: _CropPainter(cropState.cropRect, pageSize),
      child: Stack(
        children: [
          for (final handle in CropHandle.values)
            _handleWidget(handle),
        ],
      ),
    );
  }

  Widget _handleWidget(CropHandle handle) {
    final r = cropState.cropRect;
    final pos = _handlePosition(handle, r);
    return Positioned(
      left: pos.dx * pageSize.width - 8,
      top: pos.dy * pageSize.height - 8,
      child: GestureDetector(
        onPanStart: (_) => onHandleDragStart(handle),
        onPanUpdate: (d) {
          final norm = Offset(
            (pos.dx + d.delta.dx / pageSize.width).clamp(0.0, 1.0),
            (pos.dy + d.delta.dy / pageSize.height).clamp(0.0, 1.0),
          );
          onHandleDragUpdate(norm);
        },
        onPanEnd: (_) => onHandleDragEnd(),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.blue, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4),
            ],
          ),
        ),
      ),
    );
  }

  Offset _handlePosition(CropHandle handle, Rect r) {
    switch (handle) {
      case CropHandle.topLeft:
        return Offset(r.left, r.top);
      case CropHandle.topRight:
        return Offset(r.right, r.top);
      case CropHandle.bottomLeft:
        return Offset(r.left, r.bottom);
      case CropHandle.bottomRight:
        return Offset(r.right, r.bottom);
      case CropHandle.top:
        return Offset(r.center.dx, r.top);
      case CropHandle.bottom:
        return Offset(r.center.dx, r.bottom);
      case CropHandle.left:
        return Offset(r.left, r.center.dy);
      case CropHandle.right:
        return Offset(r.right, r.center.dy);
    }
  }
}

class _CropPainter extends CustomPainter {
  final Rect cropRect;
  final Size pageSize;

  _CropPainter(this.cropRect, this.pageSize);

  @override
  void paint(Canvas canvas, Size size) {
    final scaled = Rect.fromLTRB(
      cropRect.left * pageSize.width,
      cropRect.top * pageSize.height,
      cropRect.right * pageSize.width,
      cropRect.bottom * pageSize.height,
    );

    // Dim the area outside the crop.
    final dimPaint = Paint()..color = const Color(0x88000000);
    // Top bar
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, scaled.top), dimPaint);
    // Bottom bar
    canvas.drawRect(Rect.fromLTRB(0, scaled.bottom, size.width, size.height), dimPaint);
    // Left bar
    canvas.drawRect(Rect.fromLTRB(0, scaled.top, scaled.left, scaled.bottom), dimPaint);
    // Right bar
    canvas.drawRect(Rect.fromLTRB(scaled.right, scaled.top, size.width, scaled.bottom), dimPaint);

    // Crop border
    final borderPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(scaled, borderPaint);

    // Rule of thirds grid
    final gridPaint = Paint()
      ..color = Colors.blue.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;
    final w = scaled.width / 3;
    final h = scaled.height / 3;
    for (var i = 1; i < 3; i++) {
      canvas.drawLine(
        Offset(scaled.left + w * i, scaled.top),
        Offset(scaled.left + w * i, scaled.bottom),
        gridPaint,
      );
      canvas.drawLine(
        Offset(scaled.left, scaled.top + h * i),
        Offset(scaled.right, scaled.top + h * i),
        gridPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      cropRect != old.cropRect || pageSize != old.pageSize;
}
