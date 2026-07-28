import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/scanner/data/scan_ocr_service.dart';

void main() {
  group('ScanOcrService - interface contract', () {
    test('can be instantiated as a const', () {
      const svc = ScanOcrService();
      expect(svc, isNotNull);
    });

    test('is const-constructible (matching project pattern)', () {
      // All scanner services are const-constructible and stateless.
      // This verifies that the class follows the established pattern.
      const a = ScanOcrService();
      const b = ScanOcrService();
      // Two const instances of the same class are identical.
      expect(identical(a, b), isTrue);
    });

    test('exposes extractText method signature', () {
      const svc = ScanOcrService();
      // Verify the method exists and is callable (would fail at compile time
      // if the signature changed). We cannot actually run OCR without ML Kit
      // and a real image, so we only verify the interface is present.
      expect(svc.extractText, isA<Function>());
    });

    test('exposes extractWithPositions method signature', () {
      const svc = ScanOcrService();
      // Verify the method exists (compile-time contract check).
      expect(svc.extractWithPositions, isA<Function>());
    });
  });
}
