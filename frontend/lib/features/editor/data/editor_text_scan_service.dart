import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:ai_pdf/core/services/ocr_service.dart';

/// OCR-based text line scanning for the editor's "Edit existing text" flow.
class EditorTextScanService {
  const EditorTextScanService();

  Future<List<OcrLine>> scanEditableLines({
    required Uint8List bytes,
    required OcrService ocr,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/edit_${DateTime.now().microsecondsSinceEpoch}.jpg');
    await file.writeAsBytes(bytes);
    try {
      final result = await ocr.recognize(file.path);
      return result.lines
          .where((l) => l.text.trim().isNotEmpty && l.w > 0.02 && l.h > 0.004)
          .toList();
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }
}
