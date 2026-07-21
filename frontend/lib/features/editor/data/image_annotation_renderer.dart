import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';

/// Renders [ImageAnnotation] objects onto a canvas.
///
/// Handles async image decoding, caching, rotation, and opacity.
/// Used by both the on-screen painter and the export compositor.
class ImageAnnotationRenderer {
  /// Cache of decoded images keyed by annotation ID.
  final Map<String, ui.Image> _cache = {};

  /// Decode an image annotation's bytes and cache it.
  Future<ui.Image?> prepare(ImageAnnotation annotation) async {
    if (_cache.containsKey(annotation.id)) return _cache[annotation.id];
    try {
      final codec = await ui.instantiateImageCodec(annotation.bytes);
      final frame = await codec.getNextFrame();
      _cache[annotation.id] = frame.image;
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  /// Paint a prepared image annotation onto [canvas].
  void paint(Canvas canvas, Size size, ImageAnnotation annotation) {
    final image = _cache[annotation.id];
    if (image == null) return;

    final rect = Rect.fromLTWH(
      annotation.pos.dx * size.width,
      annotation.pos.dy * size.height,
      annotation.width * size.width,
      annotation.height * size.height,
    );

    canvas.save();
    if (annotation.rotation != 0) {
      canvas.translate(rect.center.dx, rect.center.dy);
      canvas.rotate(-annotation.rotation);
      canvas.translate(-rect.width / 2, -rect.height / 2);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(0, 0, rect.width, rect.height),
        Paint()..filterQuality = FilterQuality.high,
      );
    } else {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.high,
      );
    }
    canvas.restore();
  }

  /// Dispose all cached images (call on file close).
  void dispose() {
    for (final img in _cache.values) {
      img.dispose();
    }
    _cache.clear();
  }

  /// Remove a specific annotation's cached image.
  void evict(String annotationId) {
    _cache.remove(annotationId)?.dispose();
  }
}
