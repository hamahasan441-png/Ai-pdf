import 'dart:io';
import 'dart:typed_data';

import 'package:pdfx/pdfx.dart' as pdfx;

class EditorDocumentLoadResult {
  final pdfx.PdfDocument? document;
  final int pageCount;
  final Uint8List? imageBytes;

  const EditorDocumentLoadResult({
    required this.document,
    required this.pageCount,
    this.imageBytes,
  });

  bool get isPdf => document != null;
}

/// Opens a source file for the editor.
///
/// Keeps the file-type branching and basic loading mechanics out of the editor
/// screen. PDF page rasterization still happens through [EditorPageRenderService].
class EditorDocumentService {
  const EditorDocumentService();

  Future<EditorDocumentLoadResult> openDocument(String path) async {
    if (path.toLowerCase().endsWith('.pdf')) {
      final doc = await pdfx.PdfDocument.openFile(path);
      return EditorDocumentLoadResult(
        document: doc,
        pageCount: doc.pagesCount,
      );
    }

    final bytes = await File(path).readAsBytes();
    return EditorDocumentLoadResult(
      document: null,
      pageCount: 1,
      imageBytes: bytes,
    );
  }
}
