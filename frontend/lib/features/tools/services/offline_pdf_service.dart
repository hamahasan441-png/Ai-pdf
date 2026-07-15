import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// OfflinePdfService - All document operations run 100% ON-DEVICE.
///
/// Architecture decision: These tools require NO backend and NO internet.
/// The user picks files locally, everything is processed on the phone.
/// Only AI features (understanding, form fill) go online.
///
/// Engineering note: We use the raster engine from `printing` + the `pdf`
/// package instead of Syncfusion. Rationale:
///   - `printing` + `pdf` have stable, long-lived APIs (no breaking changes)
///   - No dependency on Syncfusion's frequently-changing API surface
///   - 100% offline, pure rendering pipeline
/// Trade-off: merged/split pages are rasterized (not vector text). For a
/// mobile utility this is the standard, reliable approach and also yields
/// excellent compression.
class OfflinePdfService {
  OfflinePdfService._();
  static final instance = OfflinePdfService._();

  Future<String> _outputPath(String name) async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/ai_pdf_output');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final ts = DateTime.now().millisecondsSinceEpoch;
    return '${outDir.path}/${name}_$ts';
  }

  // ==========================================================
  // JPG / IMAGES → PDF (offline)
  // ==========================================================

  Future<String> imagesToPdf(List<String> imagePaths) async {
    final doc = pw.Document();
    for (final path in imagePaths) {
      final bytes = await File(path).readAsBytes();
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(16),
          build: (context) => pw.Center(
            child: pw.Image(image, fit: pw.BoxFit.contain),
          ),
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
  // PDF MERGE (offline, raster engine)
  // ==========================================================

  /// Merge multiple PDFs into one by rendering every page and rebuilding.
  Future<String> mergePdfs(List<String> pdfPaths) async {
    final doc = pw.Document();

    for (final path in pdfPaths) {
      final bytes = await File(path).readAsBytes();
      await for (final page in Printing.raster(bytes, dpi: 150)) {
        final png = await page.toPng();
        final image = pw.MemoryImage(png);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        );
      }
    }

    final outPath = await _outputPath('merged.pdf');
    await File(outPath).writeAsBytes(await doc.save());
    return outPath;
  }

  // ==========================================================
  // PDF SPLIT (offline, raster engine)
  // ==========================================================

  /// Split a PDF into individual single-page PDFs. Returns list of paths.
  Future<List<String>> splitPdf(String pdfPath) async {
    final bytes = await File(pdfPath).readAsBytes();
    final outputs = <String>[];
    var index = 0;

    await for (final page in Printing.raster(bytes, dpi: 150)) {
      final png = await page.toPng();
      final single = pw.Document();
      final image = pw.MemoryImage(png);
      single.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
      final outPath = await _outputPath('page_${index + 1}.pdf');
      await File(outPath).writeAsBytes(await single.save());
      outputs.add(outPath);
      index++;
    }

    return outputs;
  }

  // ==========================================================
  // PDF COMPRESS (offline, raster at low DPI + JPEG re-encode)
  // ==========================================================

  Future<CompressResult> compressPdf(String pdfPath) async {
    final originalBytes = await File(pdfPath).readAsBytes();
    final originalSize = originalBytes.length;

    final doc = pw.Document();
    await for (final page in Printing.raster(originalBytes, dpi: 96)) {
      final png = await page.toPng();
      // Re-encode each page as compressed JPEG to shrink size
      final decoded = img.decodeImage(png);
      final jpg = decoded != null
          ? Uint8List.fromList(img.encodeJpg(decoded, quality: 60))
          : png;
      final image = pw.MemoryImage(jpg);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (_) => pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
        ),
      );
    }

    final outBytes = await doc.save();
    final outPath = await _outputPath('compressed.pdf');
    await File(outPath).writeAsBytes(outBytes);

    return CompressResult(
      outputPath: outPath,
      originalSize: originalSize,
      compressedSize: outBytes.length,
    );
  }

  // ==========================================================
  // PDF PAGE COUNT (offline helper)
  // ==========================================================

  Future<int> getPageCount(String pdfPath) async {
    final bytes = await File(pdfPath).readAsBytes();
    var count = 0;
    // Low DPI just to enumerate pages cheaply
    await for (final _ in Printing.raster(bytes, dpi: 12)) {
      count++;
    }
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
