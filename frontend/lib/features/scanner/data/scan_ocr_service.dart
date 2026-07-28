import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:ai_pdf/core/services/ocr_service.dart';

/// Scanner-specific OCR wrapper that takes raw image bytes, writes them to a
/// temporary file, runs OCR via [OcrService], and returns the extracted text.
///
/// This keeps the scanner feature decoupled from direct ML Kit usage and makes
/// the OCR pipeline testable (bytes-in, text-out).
class ScanOcrService {
  const ScanOcrService();

  /// Run OCR on [imageBytes] (JPEG/PNG). Writes to a temp file, extracts text,
  /// then cleans up the temp file. Returns the recognized text (may be empty).
  Future<String> extractText(Uint8List imageBytes) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().microsecondsSinceEpoch;
    final tmpPath = '${dir.path}/scan_ocr_$ts.jpg';
    final tmpFile = File(tmpPath);

    try {
      await tmpFile.writeAsBytes(imageBytes);
      final ocr = OcrService();
      try {
        final text = await ocr.recognizeText(tmpPath);
        return text.trim();
      } finally {
        await ocr.dispose();
      }
    } finally {
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Run OCR with full line-level results for searchable PDF overlay.
  Future<OcrResult> extractWithPositions(Uint8List imageBytes) async {
    final dir = await getTemporaryDirectory();
    final ts = DateTime.now().microsecondsSinceEpoch;
    final tmpPath = '${dir.path}/scan_ocr_$ts.jpg';
    final tmpFile = File(tmpPath);

    try {
      await tmpFile.writeAsBytes(imageBytes);
      final ocr = OcrService();
      try {
        return await ocr.recognize(tmpPath);
      } finally {
        await ocr.dispose();
      }
    } finally {
      try {
        if (await tmpFile.exists()) {
          await tmpFile.delete();
        }
      } catch (_) {}
    }
  }
}
