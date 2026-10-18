import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ai_pdf/core/services/ocr_service.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_page.dart';

/// Image placement in page points, measured from the top-left corner.
typedef ImageBox = ({double left, double top, double width, double height});

/// Builds the PDF for a scan session: one A4 page per scan, the image fitted
/// inside the page margins.
///
/// With [searchable], pages that have OCR text get an invisible text layer
/// (PDF text render mode 3) so the file can be searched and copied. Each OCR
/// line is placed over the part of the image it was read from: positions are
/// normalized to the image, so they are mapped into the image's fitted
/// rectangle on the page, and each line is scaled to its box. Pages without
/// line positions get the whole text as one invisible block.
class ScanPdfBuilder {
  const ScanPdfBuilder();

  static const PdfPageFormat format = PdfPageFormat.a4;

  /// Space between the page edge and the image, as before.
  static const double margin = 2.0 * PdfPageFormat.cm;

  Future<Uint8List> build(
    List<ScanPage> pages, {
    required bool searchable,
    pw.Font? textFont,
  }) {
    final doc = pw.Document();
    for (final page in pages) {
      final image = pw.MemoryImage(page.displayBytes);
      final rect = imageRect(image.width?.toDouble() ?? 1, image.height?.toDouble() ?? 1);
      final withText = searchable && page.hasOcrText;
      doc.addPage(
        pw.Page(
          pageFormat: format.copyWith(marginLeft: 0, marginTop: 0, marginRight: 0, marginBottom: 0),
          build: (_) => pw.Stack(
            children: [
              pw.Positioned(
                left: rect.left,
                top: rect.top,
                child: pw.SizedBox(
                  width: rect.width,
                  height: rect.height,
                  child: pw.Image(image, fit: pw.BoxFit.fill),
                ),
              ),
              if (withText && (page.ocrLines?.isNotEmpty ?? false))
                for (final line in page.ocrLines!)
                  if (line.text.trim().isNotEmpty && line.w > 0 && line.h > 0) _line(line, rect, textFont),
              if (withText && (page.ocrLines?.isEmpty ?? true))
                pw.Positioned(
                  left: rect.left,
                  top: rect.top,
                  child: pw.SizedBox(
                    width: rect.width,
                    child: pw.Text(
                      page.extractedText!,
                      style: _invisible(textFont, 8),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return doc.save();
  }

  /// Where the image sits on the page: the largest rectangle with the
  /// image's aspect ratio inside the margins, centred.
  static ImageBox imageRect(double imageWidth, double imageHeight) {
    final boxW = format.width - 2 * margin;
    final boxH = format.height - 2 * margin;
    final aspect = imageWidth > 0 && imageHeight > 0 ? imageWidth / imageHeight : boxW / boxH;
    var w = boxW;
    var h = w / aspect;
    if (h > boxH) {
      h = boxH;
      w = h * aspect;
    }
    return (left: margin + (boxW - w) / 2, top: margin + (boxH - h) / 2, width: w, height: h);
  }

  pw.Widget _line(OcrLine line, ImageBox rect, pw.Font? font) {
    final w = line.w * rect.width;
    final h = line.h * rect.height;
    return pw.Positioned(
      left: rect.left + line.x * rect.width,
      top: rect.top + line.y * rect.height,
      child: pw.SizedBox(
        width: w,
        height: h,
        // Stretch the run to the line's box so selecting a word highlights
        // that word in the image.
        child: pw.FittedBox(
          fit: pw.BoxFit.fill,
          child: pw.Text(line.text.trim(), style: _invisible(font, 10)),
        ),
      ),
    );
  }

  pw.TextStyle _invisible(pw.Font? font, double size) => pw.TextStyle(
        font: font,
        fontSize: size,
        renderingMode: PdfTextRenderingMode.invisible,
      );
}
