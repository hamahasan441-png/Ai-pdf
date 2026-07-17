import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../core/image/image_ops.dart';
import '../../../core/services/ocr_service.dart';

/// OfflinePdfService - All document operations run 100% ON-DEVICE.
///
/// MEMORY SAFETY (the key design goal):
///   PDF pages are rendered with pdfx at an EXPLICIT, CAPPED pixel size.
///   This bounds every allocation regardless of the source page's physical
///   size, eliminating the OutOfMemoryError that occurred with dpi-based
///   rasterization (which produced 100 MB+ bitmaps for large pages).
///
/// No backend, no internet. The user picks files locally; everything is
/// processed on the phone. Only AI features (understanding, form fill) go
/// online.
class OfflinePdfService {
  OfflinePdfService._();
  static final instance = OfflinePdfService._();

  // Resolution caps (long edge, in pixels). Bounded memory usage.
  static const int _mergeMaxEdge = 1600;
  static const int _compressMaxEdge = 1100;
  static const int _imageMaxEdge = 2000;

  Future<String> _outputPath(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/ai_pdf_output');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${outDir.path}/${name}_$ts';
  }

  /// Build an output path with the timestamp BEFORE the extension, so the file
  /// keeps a valid extension (e.g. page_1_1699999999.jpg) that the OS/file
  /// managers recognize when saved or shared.
  Future<String> _outputFile(String base, String ext) async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/ai_pdf_output');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${outDir.path}/${base}_$ts.$ext';
  }

  /// Render a single PDF page to encoded JPEG bytes at a CAPPED resolution.
  /// This is the core memory-safety primitive.
  Future<Uint8List> _renderPageCapped(
    pdfx.PdfPage page, {
    required int maxEdge,
  }) async {
    final longEdge = page.width > page.height ? page.width : page.height;
    final scale = longEdge > maxEdge ? maxEdge / longEdge : 1.0;
    final renderW = (page.width * scale).clamp(1, maxEdge.toDouble());
    final renderH = (page.height * scale).clamp(1, maxEdge.toDouble());

    final rendered = await page.render(
      width: renderW.toDouble(),
      height: renderH.toDouble(),
      format: pdfx.PdfPageImageFormat.jpeg,
      backgroundColor: '#FFFFFF',
    );
    if (rendered == null) {
      throw Exception('Failed to render PDF page');
    }
    return rendered.bytes;
  }

  // ==========================================================
  // JPG / IMAGES -> PDF (offline, with downscale guard)
  // ==========================================================

  Future<String> imagesToPdf(List<String> imagePaths) async {
    final doc = pw.Document();
    for (final path in imagePaths) {
      final rawBytes = await File(path).readAsBytes();

      // Downscale very large images off the UI thread (bounded allocations).
      final bytes = await compute(
        applyImageOp,
        ImageOp(
          type: ImageOpType.jpegDownscaleLongEdge,
          bytes: rawBytes,
          quality: 85,
          maxEdge: _imageMaxEdge,
        ),
      );

      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }
    final outPath = await _outputPath('images.pdf');
    await File(outPath).writeAsBytes(await doc.save());
    return outPath;
  }

  // ==========================================================
  // IMAGE COMPRESSION (offline, pure Dart)
  // ==========================================================

  Future<CompressResult> compressImage(
    String imagePath, {
    int quality = 70,
    int? maxWidth,
  }) async {
    final originalBytes = await File(imagePath).readAsBytes();
    final originalSize = originalBytes.length;

    // Decode/resize/encode is CPU-heavy pure Dart -> run off the UI thread.
    final compressed = await compute(
      applyImageOp,
      ImageOp(
        type: ImageOpType.jpegCompress,
        bytes: originalBytes,
        quality: quality,
        maxWidth: maxWidth,
      ),
    );
    final outPath = await _outputPath('compressed.jpg');
    await File(outPath).writeAsBytes(compressed);

    return CompressResult(
      outputPath: outPath,
      originalSize: originalSize,
      compressedSize: compressed.length,
    );
  }

  // ==========================================================
  // PDF MERGE (offline, capped render)
  // ==========================================================

  Future<String> mergePdfs(List<String> pdfPaths) async {
    final out = pw.Document();
    for (final path in pdfPaths) {
      final doc = await pdfx.PdfDocument.openFile(path);
      try {
        for (var i = 1; i <= doc.pagesCount; i++) {
          final page = await doc.getPage(i);
          try {
            final bytes = await _renderPageCapped(page, maxEdge: _mergeMaxEdge);
            final image = pw.MemoryImage(bytes);
            out.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a4,
                build: (_) =>
                    pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
              ),
            );
          } finally {
            await page.close();
          }
        }
      } finally {
        await doc.close();
      }
    }
    final outPath = await _outputPath('merged.pdf');
    await File(outPath).writeAsBytes(await out.save());
    return outPath;
  }

  // ==========================================================
  // PDF SPLIT (offline, capped render)
  // ==========================================================

  Future<List<String>> splitPdf(String pdfPath) async {
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final outputs = <String>[];
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        try {
          final bytes = await _renderPageCapped(page, maxEdge: _mergeMaxEdge);
          final single = pw.Document();
          final image = pw.MemoryImage(bytes);
          single.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (_) =>
                  pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
            ),
          );
          final outPath = await _outputPath('page_$i.pdf');
          await File(outPath).writeAsBytes(await single.save());
          outputs.add(outPath);
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    return outputs;
  }

  // ==========================================================
  // PDF COMPRESS (offline, low-res capped render + JPEG re-encode)
  // ==========================================================

  Future<CompressResult> compressPdf(String pdfPath) async {
    final originalSize = await File(pdfPath).length();
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final out = pw.Document();
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        try {
          final raw = await _renderPageCapped(page, maxEdge: _compressMaxEdge);
          // Re-encode at lower JPEG quality for extra size reduction
          // (off the UI thread; falls back to raw if it can't decode).
          final jpg = await compute(
            applyImageOp,
            ImageOp(type: ImageOpType.jpegReencode, bytes: raw, quality: 55),
          );
          final image = pw.MemoryImage(jpg);
          out.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (_) =>
                  pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
            ),
          );
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }

    final outBytes = await out.save();
    final outPath = await _outputPath('compressed.pdf');
    await File(outPath).writeAsBytes(outBytes);

    return CompressResult(
      outputPath: outPath,
      originalSize: originalSize,
      compressedSize: outBytes.length,
    );
  }

  // ==========================================================
  // PDF -> IMAGES (offline: export each page as JPG or PNG)
  // ==========================================================

  /// Render every page of [pdfPath] to a separate image file (capped
  /// resolution for bounded memory) and return the file paths in page order.
  Future<List<String>> pdfToImages(
    String pdfPath, {
    bool png = false,
    int maxEdge = _imageMaxEdge,
  }) async {
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final outputs = <String>[];
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        try {
          final longEdge = page.width > page.height ? page.width : page.height;
          final scale = longEdge > maxEdge ? maxEdge / longEdge : 1.0;
          final rendered = await page.render(
            width: (page.width * scale).clamp(1, maxEdge.toDouble()).toDouble(),
            height: (page.height * scale).clamp(1, maxEdge.toDouble()).toDouble(),
            format: png
                ? pdfx.PdfPageImageFormat.png
                : pdfx.PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          if (rendered == null) continue;
          final outPath = await _outputFile('page_$i', png ? 'png' : 'jpg');
          await File(outPath).writeAsBytes(rendered.bytes);
          outputs.add(outPath);
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    return outputs;
  }

  // ==========================================================
  // WATERMARK (offline: overlay diagonal text on every page)
  // ==========================================================

  /// Stamp a semi-transparent diagonal [text] watermark across every page.
  Future<String> watermarkPdf(
    String pdfPath,
    String text, {
    double opacity = 0.25,
  }) async {
    final label = text.trim().isEmpty ? 'CONFIDENTIAL' : text.trim();
    final op = opacity.clamp(0.05, 1.0).toDouble();
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final out = pw.Document();
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        try {
          final bytes = await _renderPageCapped(page, maxEdge: _mergeMaxEdge);
          final image = pw.MemoryImage(bytes);
          out.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (ctx) => pw.Stack(
                fit: pw.StackFit.expand,
                alignment: pw.Alignment.center,
                children: [
                  pw.Image(image, fit: pw.BoxFit.contain),
                  pw.Center(
                    child: pw.Transform.rotateBox(
                      angle: 0.6,
                      child: pw.Opacity(
                        opacity: op,
                        child: pw.Text(
                          label,
                          style: pw.TextStyle(
                            fontSize: 54,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    final outPath = await _outputFile('watermarked', 'pdf');
    await File(outPath).writeAsBytes(await out.save());
    return outPath;
  }

  // ==========================================================
  // STAMP IMAGE (offline: overlay a logo/photo/signature image)
  // ==========================================================

  /// Overlay [imagePath] onto the pages of [pdfPath] at a grid [position]
  /// (0..8, left-to-right, top-to-bottom; 4 = center), sized to [sizePct] of
  /// the page width. Applies to every page, or just the first if [firstPageOnly].
  Future<String> stampImageOnPdf(
    String pdfPath,
    String imagePath, {
    int position = 4,
    double sizePct = 0.25,
    bool firstPageOnly = false,
  }) async {
    // Load the stamp; downscale very large images off the UI thread
    // (preserving alpha as PNG).
    final rawStamp = await File(imagePath).readAsBytes();
    final stampBytes = await compute(
      applyImageOp,
      ImageOp(
        type: ImageOpType.pngDownscaleLongEdge,
        bytes: rawStamp,
        maxEdge: 1200,
      ),
    );
    final stamp = pw.MemoryImage(stampBytes);
    final align = _alignForGrid(position);
    final pct = sizePct.clamp(0.05, 0.9).toDouble();

    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final out = pw.Document();
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        try {
          final bytes = await _renderPageCapped(page, maxEdge: _mergeMaxEdge);
          final image = pw.MemoryImage(bytes);
          final apply = !firstPageOnly || i == 1;
          out.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (ctx) => pw.Stack(
                fit: pw.StackFit.expand,
                children: [
                  pw.Image(image, fit: pw.BoxFit.contain),
                  if (apply)
                    pw.Align(
                      alignment: align,
                      child: pw.Padding(
                        padding: const pw.EdgeInsets.all(20),
                        child: pw.Image(stamp,
                            width: PdfPageFormat.a4.width * pct),
                      ),
                    ),
                ],
              ),
            ),
          );
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    final outPath = await _outputFile('stamped', 'pdf');
    await File(outPath).writeAsBytes(await out.save());
    return outPath;
  }

  pw.Alignment _alignForGrid(int p) {
    switch (p) {
      case 0:
        return pw.Alignment.topLeft;
      case 1:
        return pw.Alignment.topCenter;
      case 2:
        return pw.Alignment.topRight;
      case 3:
        return pw.Alignment.centerLeft;
      case 4:
        return pw.Alignment.center;
      case 5:
        return pw.Alignment.centerRight;
      case 6:
        return pw.Alignment.bottomLeft;
      case 7:
        return pw.Alignment.bottomCenter;
      case 8:
        return pw.Alignment.bottomRight;
      default:
        return pw.Alignment.center;
    }
  }

  // ==========================================================
  // PAGE NUMBERS (offline: overlay "n / total" on every page)
  // ==========================================================

  /// Add a page-number badge (e.g. "3 / 12") to the bottom-center of each page.
  Future<String> addPageNumbers(String pdfPath) async {
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final out = pw.Document();
    final total = doc.pagesCount;
    try {
      for (var i = 1; i <= total; i++) {
        final page = await doc.getPage(i);
        try {
          final bytes = await _renderPageCapped(page, maxEdge: _mergeMaxEdge);
          final image = pw.MemoryImage(bytes);
          out.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: pw.EdgeInsets.zero,
              build: (ctx) => pw.Stack(
                fit: pw.StackFit.expand,
                children: [
                  pw.Image(image, fit: pw.BoxFit.contain),
                  pw.Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: pw.Center(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(4),
                        ),
                        child: pw.Text(
                          '$i / $total',
                          style: pw.TextStyle(
                            fontSize: 11,
                            color: PdfColors.black,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    final outPath = await _outputFile('numbered', 'pdf');
    await File(outPath).writeAsBytes(await out.save());
    return outPath;
  }

  // ==========================================================
  // PDF -> TEXT (offline: OCR each page, combine to a .txt file)
  // ==========================================================

  /// OCR every page and combine the text into a single .txt file, useful
  /// for copy/pasting or searching the full content of a scanned document.
  Future<String> pdfToText(String pdfPath) async {
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final buf = StringBuffer();
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        try {
          final longEdge = page.width > page.height ? page.width : page.height;
          final scale = longEdge > _compressMaxEdge ? _compressMaxEdge / longEdge : 1.0;
          final rendered = await page.render(
            width: (page.width * scale).clamp(1, _compressMaxEdge.toDouble()).toDouble(),
            height: (page.height * scale).clamp(1, _compressMaxEdge.toDouble()).toDouble(),
            format: pdfx.PdfPageImageFormat.jpeg,
            backgroundColor: '#FFFFFF',
          );
          if (rendered == null) continue;
          // Write temp image so OCR can process it.
          final dir = await getTemporaryDirectory();
          final tmp = '${dir.path}/pdftotext_p$i.jpg';
          await File(tmp).writeAsBytes(rendered.bytes);
          try {
            final ocr = await _ocrFile(tmp);
            if (ocr.isNotEmpty) {
              buf.writeln('--- Page $i ---');
              buf.writeln(ocr);
              buf.writeln();
            }
          } finally {
            try { await File(tmp).delete(); } catch (_) {}
          }
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    final text = buf.toString().trim();
    if (text.isEmpty) throw Exception('No text could be extracted');
    final outPath = await _outputFile('extracted_text', 'txt');
    await File(outPath).writeAsString(text);
    return outPath;
  }

  /// OCR a single image file (wrapper around google_mlkit).
  Future<String> _ocrFile(String imagePath) async {
    try {
      final ocr = OcrService();
      try {
        return await ocr.recognizeText(imagePath);
      } finally {
        await ocr.dispose();
      }
    } catch (_) {
      return '';
    }
  }

  // ==========================================================
  // EXTRACT PAGES (offline: extract a range → smaller PDF)
  // ==========================================================

  /// Extract pages [from] to [to] (1-based, inclusive) from [pdfPath].
  Future<String> extractPages(String pdfPath, {required int from, required int to}) async {
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final out = pw.Document();
    final start = from.clamp(1, doc.pagesCount);
    final end = to.clamp(start, doc.pagesCount);
    try {
      for (var i = start; i <= end; i++) {
        final page = await doc.getPage(i);
        try {
          final bytes = await _renderPageCapped(page, maxEdge: _mergeMaxEdge);
          final image = pw.MemoryImage(bytes);
          out.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
            ),
          );
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    final outPath = await _outputFile('pages_${start}_to_$end', 'pdf');
    await File(outPath).writeAsBytes(await out.save());
    return outPath;
  }

  // ==========================================================
  // DELETE PAGES (offline: remove a page range → smaller PDF)
  // ==========================================================

  /// Remove pages [from]..[to] (1-based, inclusive) and keep the rest.
  Future<String> deletePages(String pdfPath, {required int from, required int to}) async {
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final out = pw.Document();
    final total = doc.pagesCount;
    final start = from.clamp(1, total);
    final end = to.clamp(start, total);
    try {
      for (var i = 1; i <= total; i++) {
        if (i >= start && i <= end) continue; // skip deleted pages
        final page = await doc.getPage(i);
        try {
          final bytes = await _renderPageCapped(page, maxEdge: _mergeMaxEdge);
          final image = pw.MemoryImage(bytes);
          out.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
            ),
          );
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    final outPath = await _outputFile('deleted_${start}_to_$end', 'pdf');
    await File(outPath).writeAsBytes(await out.save());
    return outPath;
  }

  // ==========================================================
  // ROTATE PDF (offline: rotate all pages by a fixed angle)
  // ==========================================================

  /// Rotate every page of [pdfPath] by [degrees] (90, 180, or 270).
  Future<String> rotatePdf(String pdfPath, {int degrees = 90}) async {
    final angle = (degrees ~/ 90).clamp(1, 3); // 1=90, 2=180, 3=270
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final out = pw.Document();
    try {
      for (var i = 1; i <= doc.pagesCount; i++) {
        final page = await doc.getPage(i);
        try {
          final bytes = await _renderPageCapped(page, maxEdge: _mergeMaxEdge);
          // Decode + rotate + encode off the UI thread.
          final jpg = await compute(
            applyImageOp,
            ImageOp(
              type: ImageOpType.jpegRotate,
              bytes: bytes,
              quality: 88,
              degrees: degrees,
            ),
          );
          if (jpg.isEmpty) continue; // undecodable page -> skip
          final image = pw.MemoryImage(jpg);
          // Flip page format for 90/270 so the page matches the rotated content.
          final fmt = (angle == 1 || angle == 3)
              ? PdfPageFormat(PdfPageFormat.a4.height, PdfPageFormat.a4.width)
              : PdfPageFormat.a4;
          out.addPage(
            pw.Page(
              pageFormat: fmt,
              margin: pw.EdgeInsets.zero,
              build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
            ),
          );
        } finally {
          await page.close();
        }
      }
    } finally {
      await doc.close();
    }
    final outPath = await _outputFile('rotated', 'pdf');
    await File(outPath).writeAsBytes(await out.save());
    return outPath;
  }

  // ==========================================================
  // PAGE COUNT (offline helper)
  // ==========================================================

  Future<int> getPageCount(String pdfPath) async {
    final doc = await pdfx.PdfDocument.openFile(pdfPath);
    final count = doc.pagesCount;
    await doc.close();
    return count;
  }
}

/// Result of a compression operation.
class CompressResult {
  final String outputPath;
  final int originalSize;
  final int compressedSize;

  CompressResult({
    required this.outputPath,
    required this.originalSize,
    required this.compressedSize,
  });

  double get reductionPercent =>
      originalSize == 0 ? 0 : (1 - compressedSize / originalSize) * 100;

  String get originalSizeLabel => _fmt(originalSize);
  String get compressedSizeLabel => _fmt(compressedSize);

  static String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
