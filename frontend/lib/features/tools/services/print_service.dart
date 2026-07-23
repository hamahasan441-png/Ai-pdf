import 'dart:typed_data';

import 'package:flutter/services.dart';

/// Print service — sends PDFs to the system print dialog.
///
/// Android: uses the platform printing framework (PrintManager).
/// iOS: uses UIPrintInteractionController.
/// Both accessed via method channel.
///
/// Options:
/// - Print specific pages
/// - Number of copies
/// - Double-sided (if printer supports)
/// - Color / grayscale
class PrintService {
  static const _channel = MethodChannel('com.aidocassistant.app/print');

  const PrintService();

  /// Print a PDF from raw bytes.
  Future<bool> printPdf({
    required Uint8List pdfBytes,
    String jobName = 'AI PDF Document',
    int copies = 1,
    bool color = true,
    bool duplex = false,
    List<int>? pageRange, // null = all pages
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('print', {
        'bytes': pdfBytes,
        'jobName': jobName,
        'copies': copies,
        'color': color,
        'duplex': duplex,
        if (pageRange != null) 'pageRange': pageRange,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Print from a file path.
  Future<bool> printFile({
    required String filePath,
    String? jobName,
    int copies = 1,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('printFile', {
        'path': filePath,
        'jobName': jobName ?? filePath.split('/').last,
        'copies': copies,
      });
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Check if printing is available on this device.
  Future<bool> get isAvailable async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException {
      return false;
    }
  }
}
