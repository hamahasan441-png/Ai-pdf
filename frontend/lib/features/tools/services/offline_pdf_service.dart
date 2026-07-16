import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart' show PdfPageFormat, PdfColors;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;

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
      var bytes = await File(path).readAsBytes();

      // Downscale very large images to avoid large allocations.
      final decoded = img.decodeImage(bytes);
      if (decoded != null &&
          (decoded.width > _imageMaxEdge || decoded.height > _imageMaxEdge)) {
        final resized = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: _imageMaxEdge)
            : img.copyResize(decoded, height: _imageMaxEdge);
        bytes = Uint8List.fromList(img.encodeJpg(resized, quality: 85));
      }

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

    var decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      throw Exception('Could not decode image');
    }
    if (maxWidth != null && decoded.width > maxWidth) {
      decoded = img.copyResize(decoded, width: maxWidth);
    }

    final compressed = img.encodeJpg(decoded, quality: quality);
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
          // Re-encode at lower JPEG quality for extra size reduction.
          final decoded = img.decodeImage(raw);
          final jpg = decoded != null
              ? Uint8List.fromList(img.encodeJpg(decoded, quality: 55))
              : raw;
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
          final decoded = img.decodeImage(bytes);
          if (decoded == null) continue;
          final rotated = angle == 1
              ? img.copyRotate(decoded, angle: 90)
              : angle == 2
                  ? img.copyRotate(decoded, angle: 180)
                  : img.copyRotate(decoded, angle: 270);
          final jpg = Uint8List.fromList(img.encodeJpg(rotated, quality: 88));
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
