import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart' as pdfx;

import 'package:ai_pdf/core/services/ocr_service.dart';
import 'package:ai_pdf/features/tools/models/filled_field.dart';
import 'package:ai_pdf/features/tools/services/smart_form_filler.dart';

/// On-device smart fill orchestration for the editor.
///
/// This service OCRs the current editor page, optionally OCRs a supporting info
/// document, then runs [SmartFormFiller] to produce positioned [FilledField]s.
class EditorSmartFillService {
  const EditorSmartFillService();

  Future<List<FilledField>> smartFillPage({
    required Uint8List pageBytes,
    required OcrService pageOcr,
    required String source,
    required Map<String, String> profile,
    String? infoDocumentPath,
  }) async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;

    final pageImage = File('${dir.path}/smartfill_$stamp.jpg');
    await pageImage.writeAsBytes(pageBytes);

    try {
      final pageResult = await pageOcr.recognize(pageImage.path);
      final infoPages = source == 'doc' && infoDocumentPath != null
          ? await _ocrInfoDocument(infoDocumentPath, dir.path, stamp)
          : const <OcrResult>[];
      final info = SmartFormFiller.extractInfo(infoPages);
      return SmartFormFiller.fillForm([pageResult], info, profile);
    } finally {
      try {
        await pageImage.delete();
      } catch (_) {}
    }
  }

  Future<List<OcrResult>> _ocrInfoDocument(String path, String dirPath, int stamp) async {
    final out = <OcrResult>[];
    final ocr = OcrService();
    try {
      if (path.toLowerCase().endsWith('.pdf')) {
        final infoDoc = await pdfx.PdfDocument.openFile(path);
        try {
          final count = infoDoc.pagesCount < 10 ? infoDoc.pagesCount : 10;
          for (var i = 1; i <= count; i++) {
            final page = await infoDoc.getPage(i);
            try {
              final longEdge = page.width > page.height ? page.width : page.height;
              final scale = longEdge > 1400 ? 1400 / longEdge : 1.0;
              final img = await page.render(
                width: page.width * scale,
                height: page.height * scale,
                format: pdfx.PdfPageImageFormat.jpeg,
                backgroundColor: '#FFFFFF',
              );
              if (img?.bytes != null) {
                final p = '$dirPath/info_${stamp}_$i.jpg';
                await File(p).writeAsBytes(img!.bytes);
                out.add(await ocr.recognize(p));
                try {
                  await File(p).delete();
                } catch (_) {}
              }
            } finally {
              await page.close();
            }
          }
        } finally {
          await infoDoc.close();
        }
      } else {
        out.add(await ocr.recognize(path));
      }
    } finally {
      await ocr.dispose();
    }
    return out;
  }
}
