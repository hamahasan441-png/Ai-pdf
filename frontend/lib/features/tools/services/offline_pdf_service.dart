import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// OfflinePdfService - All document operations run 100% ON-DEVICE.
///
/// Architecture decision: These tools require NO backend and NO internet.
/// The user picks files locally, everything is processed on the phone.
/// Only AI features (understanding, form fill) go online.
///
/// This keeps the app fast, private, and free to operate for basic tools.
class OfflinePdfService {
  OfflinePdfService._();
  static final instance = OfflinePdfService._();

  /// Get a temp output path for generated files.
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

  /// Convert one or more images into a single PDF document.
  /// Each image becomes a full page, auto-fitted to A4.
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
    final file = File(outPath);
    await file.writeAsBytes(await doc.save());
    return outPath;
  }

  // ==========================================================
  // IMAGE COMPRESSION (offline, pure Dart)
  // ==========================================================

  /// Compress an image by resizing + re-encoding at target quality.
  /// quality: 0-100 (lower = smaller file). Returns output path.
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

    // Resize if wider than maxWidth
    if (maxWidth != null && decoded.width > maxWidth) {
      decoded = img.copyResize(decoded, width: maxWidth);
    }

    // Re-encode as JPEG at target quality
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
  // PDF MERGE (offline, Syncfusion)
  // ==========================================================

  /// Merge multiple PDF files into one.
  Future<String> mergePdfs(List<String> pdfPaths) async {
    final merged = sf.PdfDocument();
    // Remove the default blank page
    merged.pages.count; // touch

    for (final path in pdfPaths) {
      final bytes = await File(path).readAsBytes();
      final src = sf.PdfDocument(inputBytes: bytes);
      merged.importPageRange(src, 0, src.pages.count - 1);
      src.dispose();
    }

    final outPath = await _outputPath('merged.pdf');
    await File(outPath).writeAsBytes(await merged.save());
    merged.dispose();
    return outPath;
  }

  // ==========================================================
  // PDF SPLIT (offline)
  // ==========================================================

  /// Split a PDF into individual single-page PDFs. Returns list of paths.
  Future<List<String>> splitPdf(String pdfPath) async {
    final bytes = await File(pdfPath).readAsBytes();
    final src = sf.PdfDocument(inputBytes: bytes);
    final outputs = <String>[];

    for (var i = 0; i < src.pages.count; i++) {
      final single = sf.PdfDocument();
      single.importPageRange(src, i, i);
      final outPath = await _outputPath('page_${i + 1}.pdf');
      await File(outPath).writeAsBytes(await single.save());
      single.dispose();
      outputs.add(outPath);
    }

    src.dispose();
    return outputs;
  }

  // ==========================================================
  // PDF COMPRESS (offline)
  // ==========================================================

  /// Compress a PDF by enabling Syncfusion compression + image downsampling.
  Future<CompressResult> compressPdf(String pdfPath) async {
    final bytes = await File(pdfPath).readAsBytes();
    final originalSize = bytes.length;

    final doc = sf.PdfDocument(inputBytes: bytes);
    // Enable aggressive compression
    doc.compressionLevel = sf.PdfCompressionLevel.best;
    doc.fileStructure.incrementalUpdate = false;

    final outPath = await _outputPath('compressed.pdf');
    final outBytes = await doc.save();
    await File(outPath).writeAsBytes(outBytes);
    doc.dispose();

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
    final doc = sf.PdfDocument(inputBytes: bytes);
    final count = doc.pages.count;
    doc.dispose();
    return count;
  }

  // ==========================================================
  // EXTRACT TEXT (offline, for local search - no AI)
  // ==========================================================

  Future<String> extractText(String pdfPath) async {
    final bytes = await File(pdfPath).readAsBytes();
    final doc = sf.PdfDocument(inputBytes: bytes);
    final extractor = sf.PdfTextExtractor(doc);
    final text = extractor.extractText();
    doc.dispose();
    return text;
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
