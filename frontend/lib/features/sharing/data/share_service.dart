import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Unified sharing service — generates shareable links, exports to various
/// formats, and handles OS share sheet integration.
///
/// All operations are offline; no cloud upload required. Documents are shared
/// as file attachments via the system share sheet.
class ShareService {
  const ShareService();

  /// Share a PDF file by path via the system share sheet.
  Future<void> sharePdf(String filePath, {String? subject}) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      subject: subject ?? 'Shared PDF',
    );
  }

  /// Share raw PDF bytes (e.g. freshly exported editor output).
  /// Writes to a temp file first, then shares.
  Future<void> sharePdfBytes(Uint8List bytes, {String fileName = 'document.pdf', String? subject}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: subject ?? fileName,
    );
  }

  /// Share extracted text as a .txt file.
  Future<void> shareText(String text, {String fileName = 'extracted.txt'}) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsString(text);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/plain')],
      subject: fileName,
    );
  }

  /// Share multiple files at once (e.g. split PDF pages).
  Future<void> shareMultipleFiles(List<String> filePaths, {String? subject}) async {
    await Share.shareXFiles(
      filePaths.map((p) => XFile(p)).toList(),
      subject: subject ?? 'Shared files',
    );
  }

  /// Generate a QR-code-friendly share link (for future cloud sharing).
  /// For now returns a placeholder — will integrate with backend /share endpoint.
  String generateShareLink(String documentId) {
    return 'https://aidocassistant.com/share/$documentId';
  }
}
