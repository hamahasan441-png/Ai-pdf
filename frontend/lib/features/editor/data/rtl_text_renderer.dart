import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/editor_text_runs.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Enhanced text renderer with automatic RTL detection.
///
/// Wraps the existing AnnotationDraw.text() logic with auto-direction detection
/// so Arabic, Kurdish, Persian, and Hebrew text renders correctly without the
/// user manually setting textDirection on every annotation.
///
/// ### How it works
/// 1. If the annotation has an explicit [textDirection], use it (user override).
/// 2. Otherwise, detect from the text content using [RtlDetectionService].
/// 3. Pass the resolved direction to [TextPainter].
///
/// This does NOT modify the annotation itself (detection is runtime-only).
class RtlTextRenderer {
  const RtlTextRenderer();

  /// Paint a text annotation with auto-RTL detection.
  void paint(Canvas canvas, Size size, TextAnnotation t) {
    if (t.text.isEmpty) return;

    final tp = AnnotationTextLayout.of(t, size).painter(t);

    final px = t.pos.dx * size.width;
    final py = t.pos.dy * size.height;

    if (t.rotation != 0) {
      canvas.save();
      canvas.translate(px + tp.width / 2, py + tp.height / 2);
      canvas.rotate(-t.rotation);
      canvas.translate(-tp.width / 2, -tp.height / 2);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    } else {
      tp.paint(canvas, Offset(px, py));
    }
  }
}
