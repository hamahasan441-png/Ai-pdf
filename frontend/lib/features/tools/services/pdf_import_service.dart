import 'dart:async';
import 'package:flutter/services.dart';

/// Result from the native PDF import engine.
class PdfImportResult {
  final String status; // "success" | "unavailable" | "failed"
  final String? filePath;
  final String? strategy;
  final int? pageCount;
  final int? bytes;
  final int? elapsedMs;
  final String? reason;

  PdfImportResult({
    required this.status,
    this.filePath,
    this.strategy,
    this.pageCount,
    this.bytes,
    this.elapsedMs,
    this.reason,
  });

  factory PdfImportResult.fromMap(Map<dynamic, dynamic> map) {
    return PdfImportResult(
      status: map['status'] as String? ?? 'failed',
      filePath: map['filePath'] as String?,
      strategy: map['strategy'] as String?,
      pageCount: map['pageCount'] as int?,
      bytes: map['bytes'] as int?,
      elapsedMs: map['elapsedMs'] as int?,
      reason: map['reason'] as String?,
    );
  }

  bool get isSuccess => status == 'success';
  bool get isUnavailable => status == 'unavailable';
  bool get isFailed => status == 'failed';
}

/// Progress event streamed from the native engine during import.
class PdfImportProgress {
  final int bytesWritten;
  final int totalBytes;

  PdfImportProgress({required this.bytesWritten, required this.totalBytes});

  /// Returns 0.0–1.0 if total is known, null otherwise.
  double? get fraction =>
      totalBytes > 0 ? (bytesWritten / totalBytes).clamp(0.0, 1.0) : null;
}

/// Service that communicates with the native PdfImportEngine via platform channels.
///
/// Races 5 strategies (parallel range download, HTML link extraction, WebView
/// request interception, blob extraction, render-to-PDF) and returns the first
/// verified PDF. All strategies use only legitimate browser behavior.
class PdfImportService {
  static const _methodChannel =
      MethodChannel('com.aidocassistant.app/pdf_import');
  static const _eventChannel =
      EventChannel('com.aidocassistant.app/pdf_import_progress');

  PdfImportService._();
  static final instance = PdfImportService._();

  /// Stream of progress events during an active import.
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

  /// Import a PDF from a URL or viewer page. Returns the result with file path
  /// on success. Throws [PlatformException] on channel failures.
  Future<PdfImportResult> importPdf(String url) async {
    final result = await _methodChannel.invokeMethod<Map>('importPdf', {
      'url': url,
    });
    if (result == null) {
      return PdfImportResult(status: 'failed', reason: 'no response from engine');
    }
    return PdfImportResult.fromMap(result);
  }

  /// Cancel a running import.
  Future<void> cancelImport() async {
    await _methodChannel.invokeMethod('cancelImport');
  }
}
