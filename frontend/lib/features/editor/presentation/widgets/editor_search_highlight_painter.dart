import 'dart:ui' show Rect;

import 'package:flutter/material.dart';

/// Custom painter that highlights search match rects on the current page
/// (Phase 27).
///
/// Receives normalised 0..1 [matchRects] and draws translucent yellow overlays
/// (or orange for the active match) on the canvas, scaled to the [pageSize] the
/// document viewport is rendering at.
class EditorSearchHighlightPainter extends CustomPainter {
  /// All match rects for the current page (normalised 0..1).
  final List<Rect> matchRects;

  /// The index within [matchRects] of the currently focused match (drawn
  /// brighter/orange). -1 means no focus.
  final int activeIndex;

  /// The rendered size of the page (pixels). Used to scale normalised coords.
  final Size pageSize;

  EditorSearchHighlightPainter({
    required this.matchRects,
    required this.activeIndex,
    required this.pageSize,
  });

  static final Paint _passivePaint = Paint()
    ..color = const Color(0x55FFEB3B)
    ..style = PaintingStyle.fill;

  static final Paint _activePaint = Paint()
    ..color = const Color(0x88FF9800)
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < matchRects.length; i++) {
      final normalized = matchRects[i];
      final scaled = Rect.fromLTWH(
        normalized.left * pageSize.width,
        normalized.top * pageSize.height,
        normalized.width * pageSize.width,
        normalized.height * pageSize.height,
      );
      canvas.drawRect(scaled, i == activeIndex ? _activePaint : _passivePaint);
    }
  }

  @override
  bool shouldRepaint(EditorSearchHighlightPainter oldDelegate) {
    return matchRects != oldDelegate.matchRects ||
        activeIndex != oldDelegate.activeIndex ||
        pageSize != oldDelegate.pageSize;
  }
}
