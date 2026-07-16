import 'dart:io';
import 'dart:ui' as ui;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// One recognized line of text with its position, normalized 0..1 relative to
/// the page image (x/y = top-left, w/h = size). Used for on-device text
/// extraction now, and precise form-field placement later.
class OcrLine {
  final String text;
  final double x;
  final double y;
  final double w;
  final double h;
  const OcrLine(this.text, this.x, this.y, this.w, this.h);
}

class OcrResult {
  final String text;
  final List<OcrLine> lines;
  const OcrResult(this.text, this.lines);
}

/// On-device OCR via Google ML Kit (bundled Latin model, fully offline).
///
/// Reusable: keep one instance, call [recognize] as needed, and [dispose] when
/// done. All work happens on-device — nothing is uploaded.
class OcrService {
  final TextRecognizer _recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);

  /// Plain recognized text for [imagePath].
  Future<String> recognizeText(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);
    return result.text;
  }

  /// Full result: text plus per-line normalized boxes.
  Future<OcrResult> recognize(String imagePath) async {
    final input = InputImage.fromFilePath(imagePath);
    final result = await _recognizer.processImage(input);

    // ML Kit reports pixel rectangles; normalize using the image dimensions.
    double iw = 0, ih = 0;
    try {
      final bytes = await File(imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      iw = frame.image.width.toDouble();
      ih = frame.image.height.toDouble();
      frame.image.dispose();
    } catch (_) {
      // If we can't get dimensions, boxes stay empty but text still works.
    }

    final lines = <OcrLine>[];
    if (iw > 0 && ih > 0) {
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final r = line.boundingBox;
          lines.add(OcrLine(
            line.text,
            (r.left / iw).clamp(0.0, 1.0),
            (r.top / ih).clamp(0.0, 1.0),
            (r.width / iw).clamp(0.0, 1.0),
            (r.height / ih).clamp(0.0, 1.0),
          ));
        }
      }
    }
    return OcrResult(result.text, lines);
  }

  Future<void> dispose() => _recognizer.close();
}
