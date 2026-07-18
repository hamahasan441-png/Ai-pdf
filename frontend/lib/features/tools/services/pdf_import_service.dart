import 'dart:async';
import 'package:flutter/services.dart';

/// Result of importing a file (PDF or any other type) from a URL.
class ImportedFile {
  final String status; // "success" | "unavailable" | "failed"
  final String? filePath;
  final String? fileName;
  final String? mimeType;
  final int? bytes;
  final int? pageCount; // non-null only for PDFs
  final String? strategy;
  final int? elapsedMs;
  final int? avgBytesPerSec;
  final int? retries;
  final int? resumedBytes;
  final String? reason;

  ImportedFile({
    required this.status,
    this.filePath,
    this.fileName,
    this.mimeType,
    this.bytes,
    this.pageCount,
    this.strategy,
    this.elapsedMs,
    this.avgBytesPerSec,
    this.retries,
    this.resumedBytes,
    this.reason,
  });

  factory ImportedFile.fromMap(Map<dynamic, dynamic> map) {
    return ImportedFile(
      status: map['status'] as String? ?? 'failed',
      filePath: map['filePath'] as String?,
      fileName: map['fileName'] as String?,
      mimeType: map['mimeType'] as String?,
      bytes: (map['bytes'] as num?)?.toInt(),
      pageCount: (map['pageCount'] as num?)?.toInt(),
      strategy: map['strategy'] as String?,
      elapsedMs: (map['elapsedMs'] as num?)?.toInt(),
      avgBytesPerSec: (map['avgBytesPerSec'] as num?)?.toInt(),
      retries: (map['retries'] as num?)?.toInt(),
      resumedBytes: (map['resumedBytes'] as num?)?.toInt(),
      reason: map['reason'] as String?,
    );
  }

  /// Human-readable resumed amount (bytes recovered from a prior interrupted run).
  String? get readableResumed {
    final r = resumedBytes ?? 0;
    if (r <= 0) return null;
    if (r >= 1024 * 1024) return '${(r / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (r >= 1024) return '${(r / 1024).toStringAsFixed(0)} KB';
    return '$r B';
  }

  /// Human-readable download speed, e.g. "4.2 MB/s".
  String? get readableSpeed {
    final s = avgBytesPerSec;
    if (s == null || s <= 0) return null;
    if (s >= 1024 * 1024) return '${(s / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    if (s >= 1024) return '${(s / 1024).toStringAsFixed(0)} KB/s';
    return '$s B/s';
  }

  bool get isSuccess => status == 'success';
  bool get isUnavailable => status == 'unavailable';
  bool get isFailed => status == 'failed';

  bool get isPdf => mimeType == 'application/pdf';
  bool get isImage => (mimeType ?? '').startsWith('image/');

  /// Human-readable file size.
  String get readableSize {
    final b = bytes ?? 0;
    if (b >= 1024 * 1024) return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (b >= 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    return '$b B';
  }
}

/// Result of a "Save as" operation.
class SaveResult {
  final bool saved;
  final String? uri;
  final String? reason;
  SaveResult({required this.saved, this.uri, this.reason});

  factory SaveResult.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return SaveResult(saved: false, reason: 'no response');
    return SaveResult(
      saved: map['saved'] as bool? ?? false,
      uri: map['uri'] as String?,
      reason: map['reason'] as String?,
    );
  }
}

/// Progress event streamed from the native engine during download.
class PdfImportProgress {
  final int bytesWritten;
  final int totalBytes;
  PdfImportProgress({required this.bytesWritten, required this.totalBytes});

  double? get fraction =>
      totalBytes > 0 ? (bytesWritten / totalBytes).clamp(0.0, 1.0) : null;
}

/// Communicates with the native download/import engine via platform channels.
///
/// - [importPdf]  races 5 strategies for a verified PDF (viewer pages, blobs, etc.)
/// - [importFile] downloads ANY file type via a fast parallel range download
/// - [saveFile]   opens the system "Save as" dialog and writes to the chosen spot
///
/// All strategies use only legitimate browser behavior.
class PdfImportService {
  static const _methodChannel =
      MethodChannel('com.aidocassistant.app/pdf_import');
  static const _eventChannel =
      EventChannel('com.aidocassistant.app/pdf_import_progress');

  PdfImportService._();
  static final instance = PdfImportService._();

  Stream<PdfImportProgress> get progressStream => _eventChannel
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) {
    final map = event as Map;
    return PdfImportProgress(
      bytesWritten: (map['bytesWritten'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? -1,
    );
  });

  /// Download any file (PDF, image, doc, zip, media, ...) from a URL.
  Future<ImportedFile> importFile(String url) async {
    final result =
        await _methodChannel.invokeMethod<Map>('importFile', {'url': url});
    if (result == null) {
      return ImportedFile(status: 'failed', reason: 'no response from engine');
    }
    return ImportedFile.fromMap(result);
  }

  /// Import specifically as a PDF (uses the 5-strategy race for viewer pages).
  Future<ImportedFile> importPdf(String url) async {
    final result =
        await _methodChannel.invokeMethod<Map>('importPdf', {'url': url});
    if (result == null) {
      return ImportedFile(status: 'failed', reason: 'no response from engine');
    }
    return ImportedFile.fromMap(result);
  }

  /// Open the system "Save as" dialog so the user picks where to store the file.
  Future<SaveResult> saveFile({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    final result = await _methodChannel.invokeMethod<Map>('saveFile', {
      'sourcePath': sourcePath,
      'fileName': fileName,
      'mimeType': mimeType,
    });
    return SaveResult.fromMap(result);
  }

  Future<void> cancelImport() async {
    await _methodChannel.invokeMethod('cancelImport');
  }
}
