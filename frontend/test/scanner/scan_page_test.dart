import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/core/services/ocr_service.dart';
import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_filter.dart';
import 'package:ai_pdf/features/scanner/domain/entities/scan_page.dart';

void main() {
  final dummyBytes = Uint8List.fromList([0, 1, 2, 3]);
  final corners = DocumentCorners.fullFrame(const Size(100, 100));

  ScanPage makePage({
    String? extractedText,
    bool ocrProcessing = false,
  }) {
    return ScanPage(
      id: 'test_1',
      originalBytes: dummyBytes,
      corners: corners,
      extractedText: extractedText,
      ocrProcessing: ocrProcessing,
    );
  }

  group('ScanPage - extractedText field', () {
    test('defaults to null when not provided', () {
      final page = makePage();
      expect(page.extractedText, isNull);
    });

    test('stores extracted text when provided', () {
      final page = makePage(extractedText: 'Hello World');
      expect(page.extractedText, equals('Hello World'));
    });

    test('hasOcrText returns false when extractedText is null', () {
      final page = makePage();
      expect(page.hasOcrText, isFalse);
    });

    test('hasOcrText returns false when extractedText is empty', () {
      final page = makePage(extractedText: '');
      expect(page.hasOcrText, isFalse);
    });

    test('hasOcrText returns true when extractedText is non-empty', () {
      final page = makePage(extractedText: 'Some OCR text');
      expect(page.hasOcrText, isTrue);
    });
  });

  group('ScanPage - ocrProcessing flag', () {
    test('defaults to false', () {
      final page = makePage();
      expect(page.ocrProcessing, isFalse);
    });

    test('can be set to true', () {
      final page = makePage(ocrProcessing: true);
      expect(page.ocrProcessing, isTrue);
    });
  });

  group('ScanPage - copyWith for OCR fields', () {
    test('copyWith preserves extractedText when not overridden', () {
      final page = makePage(extractedText: 'existing text');
      final copied = page.copyWith(filter: ScanFilter.grayscale);
      expect(copied.extractedText, equals('existing text'));
      expect(copied.filter, equals(ScanFilter.grayscale));
    });

    test('copyWith updates extractedText', () {
      final page = makePage();
      final copied = page.copyWith(extractedText: 'new text');
      expect(copied.extractedText, equals('new text'));
    });

    test('copyWith preserves ocrProcessing when not overridden', () {
      final page = makePage(ocrProcessing: true);
      final copied = page.copyWith(filter: ScanFilter.original);
      expect(copied.ocrProcessing, isTrue);
    });

    test('copyWith updates ocrProcessing', () {
      final page = makePage();
      final copied = page.copyWith(ocrProcessing: true);
      expect(copied.ocrProcessing, isTrue);
    });

    test('copyWith with clearOcrText sets extractedText to null', () {
      final page = makePage(extractedText: 'will be cleared');
      final copied = page.copyWith(clearOcrText: true);
      expect(copied.extractedText, isNull);
    });

    test('clearOcrText takes precedence over extractedText parameter', () {
      final page = makePage(extractedText: 'existing');
      final copied =
          page.copyWith(extractedText: 'new value', clearOcrText: true);
      expect(copied.extractedText, isNull);
    });

    test('copyWith does not affect other fields', () {
      final page = makePage(extractedText: 'text', ocrProcessing: true);
      final copied = page.copyWith(extractedText: 'updated');
      expect(copied.id, equals('test_1'));
      expect(copied.originalBytes, same(dummyBytes));
      expect(copied.corners, equals(corners));
      expect(copied.filter, equals(ScanFilter.auto));
      expect(copied.rotationQuarterTurns, equals(0));
      expect(copied.processing, isFalse);
    });
  });

  group('ScanPage - displayBytes', () {
    test('returns originalBytes when processedBytes is null', () {
      final page = makePage();
      expect(page.displayBytes, same(dummyBytes));
    });

    test('returns processedBytes when available', () {
      final processed = Uint8List.fromList([10, 20, 30]);
      final page = makePage();
      final updated = page.copyWith(processedBytes: processed);
      expect(updated.displayBytes, same(processed));
    });
  });

  group('ScanPage - rotatedCW', () {
    test('increments rotation and clears processed bytes', () {
      final processed = Uint8List.fromList([10, 20, 30]);
      final page = makePage();
      final withProcessed = page.copyWith(processedBytes: processed);
      final rotated = withProcessed.rotatedCW();
      expect(rotated.rotationQuarterTurns, equals(1));
      expect(rotated.processedBytes, isNull);
    });

    test('wraps rotation at 4', () {
      var page = makePage();
      page = page.copyWith(rotationQuarterTurns: 3);
      final rotated = page.rotatedCW();
      expect(rotated.rotationQuarterTurns, equals(0));
    });
  });

  group('ScanPage - ocrLines field', () {
    test('defaults to null when not provided', () {
      final page = makePage();
      expect(page.ocrLines, isNull);
    });

    test('stores OCR line positions when provided', () {
      final lines = [
        const OcrLine('Hello', 0.1, 0.2, 0.3, 0.04),
        const OcrLine('World', 0.1, 0.3, 0.3, 0.04),
      ];
      final page = ScanPage(
        id: 'test_1',
        originalBytes: dummyBytes,
        corners: corners,
        ocrLines: lines,
      );
      expect(page.ocrLines, isNotNull);
      expect(page.ocrLines!.length, equals(2));
      expect(page.ocrLines![0].text, equals('Hello'));
    });

    test('copyWith preserves ocrLines when not overridden', () {
      final lines = [const OcrLine('Test', 0.0, 0.0, 0.5, 0.05)];
      final page = ScanPage(
        id: 'test_1',
        originalBytes: dummyBytes,
        corners: corners,
        ocrLines: lines,
      );
      final copied = page.copyWith(extractedText: 'Test');
      expect(copied.ocrLines, same(lines));
    });

    test('clearOcrText also clears ocrLines', () {
      final lines = [const OcrLine('Test', 0.0, 0.0, 0.5, 0.05)];
      final page = ScanPage(
        id: 'test_1',
        originalBytes: dummyBytes,
        corners: corners,
        extractedText: 'Test',
        ocrLines: lines,
      );
      final cleared = page.copyWith(clearOcrText: true);
      expect(cleared.extractedText, isNull);
      expect(cleared.ocrLines, isNull);
    });
  });

  group('ScanPage - ocrFailed flag', () {
    test('defaults to false', () {
      final page = makePage();
      expect(page.ocrFailed, isFalse);
    });

    test('can be set via copyWith', () {
      final page = makePage();
      final failed = page.copyWith(ocrFailed: true);
      expect(failed.ocrFailed, isTrue);
    });

    test('clearOcrText resets ocrFailed via new page creation', () {
      final page = ScanPage(
        id: 'test_1',
        originalBytes: dummyBytes,
        corners: corners,
        ocrFailed: true,
      );
      final cleared = page.copyWith(clearOcrText: true, ocrFailed: false);
      expect(cleared.ocrFailed, isFalse);
    });
  });
}
