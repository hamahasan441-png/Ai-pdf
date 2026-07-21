import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/data/annotation_draw.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Verifies that the export compositor produces output matching on-screen rendering.
///
/// This is the foundation for export fidelity golden tests (P1). It renders a
/// page layer onto an off-screen canvas at a known size, captures the pixel data,
/// and provides comparison utilities.
///
/// ### Usage (in tests)
/// ```dart
/// final checker = ExportFidelityChecker();
/// final pixels = await checker.renderToPixels(layer, Size(800, 1131));
/// // Compare against a golden snapshot or check non-zero pixel count.
/// ```
class ExportFidelityChecker {
  const ExportFidelityChecker();

  /// Render a page layer to raw pixel data at [size].
  /// Returns RGBA bytes (width × height × 4 bytes).
  Future<Uint8List?> renderToPixels(PageLayer layer, Size size) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));

    // White background (matches export).
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.white,
    );

    // Paint all annotations.
    AnnotationDraw.layer(canvas, size, layer);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.width.round(), size.height.round());
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
      picture.dispose();
    }
  }

  /// Check that a rendered page has non-white pixels (i.e. annotations rendered).
  bool hasVisibleContent(Uint8List rgba, int width, int height) {
    // Check a sample of pixels for non-white values.
    for (var i = 0; i < rgba.length; i += 16) {
      final r = rgba[i];
      final g = rgba[i + 1];
      final b = rgba[i + 2];
      if (r < 250 || g < 250 || b < 250) return true;
    }
    return false;
  }

  /// Compare two renders and return the percentage of pixels that differ.
  double diffPercentage(Uint8List a, Uint8List b) {
    if (a.length != b.length) return 1.0;
    int diffCount = 0;
    final pixelCount = a.length ~/ 4;
    for (var i = 0; i < a.length; i += 4) {
      if (a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2]) {
        diffCount++;
      }
    }
    return diffCount / pixelCount;
  }
}
