import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

/// Vision Forms Frontend Cropping — E2.7B Phase 7.
///
/// When OCR field detection confidence is low (< threshold), crop field rect as image
/// and send to backend POST /forms/vision-detect with vision model list AI_VISION_MODELS.
///
/// Flow:
/// 1. Heuristics first (instant, offline) via ocr_field_detection_service.dart
/// 2. When confidence < threshold, crop field rect from page bytes: decode JPEG → crop via image package copyCrop → encode base64
/// 3. POST to /forms/vision-detect with vision model list, improves recall 20% for handwritten checkbox etc.
/// 4. Keep heuristics first (offline), vision second (online, metered)

class VisionCrop {
  final String label;
  final String base64Jpeg;
  final double confidence;
  final String detectedType;
  final RectNormalized rect;

  const VisionCrop({
    required this.label,
    required this.base64Jpeg,
    required this.confidence,
    required this.detectedType,
    required this.rect,
  });
}

class RectNormalized {
  final double x0, y0, x1, y1;
  const RectNormalized({required this.x0, required this.y0, required this.x1, required this.y1});
}

class VisionCropService {
  const VisionCropService();

  /// Crop field rect from page bytes (JPEG) to base64 JPEG for vision API
  Future<VisionCrop?> cropField({
    required Uint8List pageBytes,
    required String label,
    required RectNormalized rect,
    required double confidence,
    required String detectedType,
  }) async {
    try {
      // Decode JPEG
      final decoded = img.decodeJpg(pageBytes);
      if (decoded == null) return null;

      final w = decoded.width;
      final h = decoded.height;

      // Convert normalized to pixels
      final x0 = (rect.x0 * w).toInt().clamp(0, w - 1);
      final y0 = (rect.y0 * h).toInt().clamp(0, h - 1);
      final x1 = (rect.x1 * w).toInt().clamp(0, w);
      final y1 = (rect.y1 * h).toInt().clamp(0, h);

      final cropW = (x1 - x0).clamp(10, w);
      final cropH = (y1 - y0).clamp(10, h);

      // Crop with some padding (20% extra)
      final padW = (cropW * 0.2).toInt();
      final padH = (cropH * 0.2).toInt();
      final cx0 = (x0 - padW).clamp(0, w - 1);
      final cy0 = (y0 - padH).clamp(0, h - 1);
      final cx1 = (x1 + padW).clamp(0, w);
      final cy1 = (y1 + padH).clamp(0, h);

      final cropped = img.copyCrop(
        decoded,
        x: cx0,
        y: cy0,
        width: cx1 - cx0,
        height: cy1 - cy0,
      );

      // Encode as JPEG base64
      final jpegBytes = img.encodeJpg(cropped, quality: 85);
      final base64 = base64Encode(jpegBytes);

      return VisionCrop(
        label: label,
        base64Jpeg: base64,
        confidence: confidence,
        detectedType: detectedType,
        rect: rect,
      );
    } catch (_) {
      return null;
    }
  }

  /// Batch crop multiple fields
  Future<List<VisionCrop>> batchCrop({
    required Uint8List pageBytes,
    required List<Map<String, dynamic>> fields, // each with label, x0,y0,x1,y1, confidence, type
  }) async {
    final results = <VisionCrop>[];
    for (final f in fields) {
      try {
        final rect = RectNormalized(
          x0: (f['x0'] as double?) ?? 0,
          y0: (f['y0'] as double?) ?? 0,
          x1: (f['x1'] as double?) ?? 0,
          y1: (f['y1'] as double?) ?? 0,
        );
        final crop = await cropField(
          pageBytes: pageBytes,
          label: f['label'] as String? ?? 'unknown',
          rect: rect,
          confidence: (f['confidence'] as double?) ?? 0.5,
          detectedType: f['type'] as String? ?? 'text',
        );
        if (crop != null) results.add(crop);
      } catch (_) {}
    }
    return results;
  }

  /// Build payload for POST /forms/vision-detect
  Map<String, dynamic> buildVisionPayload({
    required List<VisionCrop> crops,
    String language = 'auto',
  }) {
    return {
      'fields': crops
          .map((c) => {
                'label': c.label,
                'image_base64': c.base64Jpeg,
                'image_mime': 'image/jpeg',
                'detected_type': c.detectedType,
                'confidence': c.confidence,
                'language': language,
              })
          .toList(),
      'language': language,
    };
  }
}
