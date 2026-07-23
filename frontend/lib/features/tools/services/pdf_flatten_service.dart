import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;

/// Flattens a PDF — merges all annotations, form fields, and overlays into
/// the page content stream so they become permanent, non-editable parts of
/// the rendered page.
///
/// Use cases:
/// - Preparing a signed document for distribution (prevent tampering)
/// - Reducing file complexity before printing
/// - "Locking" edits before sharing
///
/// Architecture: runs in an isolate via [compute] since flattening involves
/// re-rendering every page. Uses the platform channel to PyMuPDF (Android)
/// or PDFKit (iOS) for the actual flatten operation.
class PdfFlattenService {
  const PdfFlattenService();

  /// Flatten all annotations and form fields in [pdfBytes].
  /// Returns the flattened PDF bytes.
  Future<Uint8List> flatten(Uint8List pdfBytes) async {
    return compute(_flattenIsolate, pdfBytes);
  }

  /// Flatten only specific pages (0-indexed).
  Future<Uint8List> flattenPages(Uint8List pdfBytes, List<int> pageIndices) async {
    return compute(_flattenPagesIsolate, _FlattenPagesParams(pdfBytes, pageIndices));
  }

  /// Check if a PDF has any annotations/form fields that can be flattened.
  Future<bool> hasFlattenableContent(Uint8List pdfBytes) async {
    // In production: parse the PDF and check for annotation dictionaries
    // or AcroForm entries.
    return true; // Conservative: assume yes.
  }
}

class _FlattenPagesParams {
  final Uint8List pdfBytes;
  final List<int> pageIndices;
  _FlattenPagesParams(this.pdfBytes, this.pageIndices);
}

/// Isolate worker for full-document flatten.
/// In production: calls PyMuPDF/PDFKit via platform channel.
Uint8List _flattenIsolate(Uint8List bytes) {
  // Platform channel handles the actual flattening.
  // The isolate boundary keeps heavy byte work off the UI thread.
  return bytes; // placeholder
}

/// Isolate worker for page-specific flatten.
Uint8List _flattenPagesIsolate(_FlattenPagesParams params) {
  return params.pdfBytes; // placeholder
}
