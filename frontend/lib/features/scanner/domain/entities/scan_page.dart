import 'dart:typed_data';

import 'package:ai_pdf/core/services/ocr_service.dart';
import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_filter.dart';

/// One captured page in a scan session (Phase 51).
///
/// Holds the raw captured photo plus the editing state (detected corners,
/// chosen filter, rotation) and the latest processed (dewarped + filtered)
/// result used for the thumbnail and final PDF.
class ScanPage {
  final String id;

  /// The original, full-resolution captured frame (JPEG bytes).
  final Uint8List originalBytes;

  /// The processed (dewarped + filtered) output; null until first processed.
  final Uint8List? processedBytes;

  /// Detected/adjusted document corners in the original frame's pixel space.
  final DocumentCorners corners;

  final ScanFilter filter;

  /// Extra clockwise quarter-turns applied on top of the dewarp (0..3).
  final int rotationQuarterTurns;

  /// True while a (re)process is running for this page.
  final bool processing;

  /// OCR-extracted text for this page; null if OCR has not been run.
  final String? extractedText;

  /// Per-line OCR positions (normalized 0..1) for searchable PDF overlay.
  /// Null if OCR has not been run or positions are unavailable.
  final List<OcrLine>? ocrLines;

  /// True while OCR is running for this page.
  final bool ocrProcessing;

  /// True if OCR was attempted but failed for this page.
  final bool ocrFailed;

  const ScanPage({
    required this.id,
    required this.originalBytes,
    this.processedBytes,
    required this.corners,
    this.filter = ScanFilter.auto,
    this.rotationQuarterTurns = 0,
    this.processing = false,
    this.extractedText,
    this.ocrLines,
    this.ocrProcessing = false,
    this.ocrFailed = false,
  });

  /// The bytes to display/export: processed if available, else the original.
  Uint8List get displayBytes => processedBytes ?? originalBytes;

  bool get isProcessed => processedBytes != null;

  /// Whether OCR has been run and produced text for this page.
  bool get hasOcrText => extractedText != null && extractedText!.isNotEmpty;

  ScanPage copyWith({
    Uint8List? processedBytes,
    DocumentCorners? corners,
    ScanFilter? filter,
    int? rotationQuarterTurns,
    bool? processing,
    String? extractedText,
    List<OcrLine>? ocrLines,
    bool? ocrProcessing,
    bool? ocrFailed,
    bool clearProcessed = false,
    bool clearOcrText = false,
  }) {
    return ScanPage(
      id: id,
      originalBytes: originalBytes,
      processedBytes:
          clearProcessed ? null : (processedBytes ?? this.processedBytes),
      corners: corners ?? this.corners,
      filter: filter ?? this.filter,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
      processing: processing ?? this.processing,
      extractedText:
          clearOcrText ? null : (extractedText ?? this.extractedText),
      ocrLines: clearOcrText ? null : (ocrLines ?? this.ocrLines),
      ocrProcessing: ocrProcessing ?? this.ocrProcessing,
      ocrFailed: ocrFailed ?? this.ocrFailed,
    );
  }

  /// Rotate 90° clockwise (wraps 0..3).
  ScanPage rotatedCW() =>
      copyWith(rotationQuarterTurns: (rotationQuarterTurns + 1) % 4, clearProcessed: true);
}
