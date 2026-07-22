import 'dart:ui' show Rect;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/application/editor_redaction_controller.dart';

/// Overlay that visualises pending redaction regions and the live drag rect
/// (Phase 28).
///
/// Renders translucent red rectangles for pending regions, and a dashed outline
/// for the in‑progress drag. The caller positions this as a layer above the
/// document viewport (same coordinate space).
class EditorRedactionOverlay extends StatelessWidget {
  final EditorRedactionState redactionState;
  final Size pageSize;
  final int currentPage;

  const EditorRedactionOverlay({
    super.key,
    required this.redactionState,
    required this.pageSize,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: pageSize,
      painter: _RedactionPainter(
        pending: [
          for (final p in redactionState.pending)
            if (p.pageIndex == currentPage) p.rect,
        ],
        liveRect: redactionState.liveRect,
        pageSize: pageSize,
      ),
    );
  }
}

class _RedactionPainter extends CustomPainter {
  final List<Rect> pending;
  final Rect? liveRect;
  final Size pageSize;

  _RedactionPainter({
    required this.pending,
    required this.liveRect,
    required this.pageSize,
  });

  static final Paint _pendingPaint = Paint()
    ..color = const Color(0x66F44336)
    ..style = PaintingStyle.fill;

  static final Paint _liveBorder = Paint()
    ..color = const Color(0xCCF44336)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  static final Paint _liveFill = Paint()
    ..color = const Color(0x33F44336)
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in pending) {
      canvas.drawRect(_scale(r), _pendingPaint);
    }
    if (liveRect != null) {
      final scaled = _scale(liveRect!);
      canvas.drawRect(scaled, _liveFill);
      canvas.drawRect(scaled, _liveBorder);
    }
  }

  Rect _scale(Rect normalised) => Rect.fromLTWH(
        normalised.left * pageSize.width,
        normalised.top * pageSize.height,
        normalised.width * pageSize.width,
        normalised.height * pageSize.height,
      );

  @override
  bool shouldRepaint(_RedactionPainter old) =>
      pending != old.pending ||
      liveRect != old.liveRect ||
      pageSize != old.pageSize;
}
