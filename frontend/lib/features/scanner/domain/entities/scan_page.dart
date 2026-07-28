import 'dart:typed_data';

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

  /// True while OCR is running for this page.
  final bool ocrProcessing;

  const ScanPage({
    required this.id,
    required this.originalBytes,
    this.processedBytes,
    required this.corners,
    this.filter = ScanFilter.auto,
    this.rotationQuarterTurns = 0,
    this.processing = false,
    this.extractedText,
    this.ocrProcessing = false,
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
    bool? ocrProcessing,
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
      ocrProcessing: ocrProcessing ?? this.ocrProcessing,
    );
  }

  /// Rotate 90° clockwise (wraps 0..3).
  ScanPage rotatedCW() =>
      copyWith(rotationQuarterTurns: (rotationQuarterTurns + 1) % 4, clearProcessed: true);
}
