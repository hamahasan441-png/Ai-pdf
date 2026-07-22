import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';
import 'package:ai_pdf/features/scanner/domain/services/document_detection_service.dart';

void main() {
  const svc = DocumentDetectionService();
  const frame = Size(1000, 1400);

  group('DocumentDetectionService.isValidDocumentQuad', () {
    test('accepts a well-sized centred document', () {
      const c = DocumentCorners(
        topLeft: Offset(150, 200),
        topRight: Offset(850, 200),
        bottomRight: Offset(850, 1150),
        bottomLeft: Offset(150, 1150),
      );
      expect(svc.isValidDocumentQuad(c, frame), isTrue);
    });

    test('rejects a tiny quad below the min area ratio', () {
      const c = DocumentCorners(
        topLeft: Offset(10, 10),
        topRight: Offset(120, 10),
        bottomRight: Offset(120, 120),
        bottomLeft: Offset(10, 120),
      );
      expect(svc.isValidDocumentQuad(c, frame), isFalse);
    });

    test('rejects a non-convex quad', () {
      const c = DocumentCorners(
        topLeft: Offset(150, 200),
        topRight: Offset(850, 1150), // crossed
        bottomRight: Offset(850, 200),
        bottomLeft: Offset(150, 1150),
      );
      expect(svc.isValidDocumentQuad(c, frame), isFalse);
    });

    test('rejects an extreme aspect ratio (thin sliver)', () {
      const c = DocumentCorners(
        topLeft: Offset(10, 100),
        topRight: Offset(990, 100),
        bottomRight: Offset(990, 150),
        bottomLeft: Offset(10, 150),
      );
      // width ~980, height ~50 -> aspect ~19.6 > maxAspect
      expect(svc.isValidDocumentQuad(c, frame), isFalse);
    });
  });

  group('DocumentDetectionService.detectBest', () {
    test('picks the higher-scoring rectangular candidate', () {
      final goodRect = [
        const Offset(150, 200),
        const Offset(850, 200),
        const Offset(850, 1150),
        const Offset(150, 1150),
      ];
      final skewedSmall = [
        const Offset(400, 500),
        const Offset(520, 480),
        const Offset(540, 650),
        const Offset(390, 640),
      ];
      final result = svc.detectBest([skewedSmall, goodRect], frame);
      expect(result.isFallback, isFalse);
      expect(result.confidence, greaterThan(0));
      // Should have chosen the large well-framed rectangle.
      expect(result.corners.topLeft.dx, closeTo(150, 1));
      expect(result.corners.bottomRight.dy, closeTo(1150, 1));
    });

    test('falls back to an inset frame when no candidate qualifies', () {
      final tiny = [
        const Offset(10, 10),
        const Offset(30, 10),
        const Offset(30, 30),
        const Offset(10, 30),
      ];
      final result = svc.detectBest([tiny], frame);
      expect(result.isFallback, isTrue);
      expect(result.confidence, 0);
      // Inset frame ~4%.
      expect(result.corners.topLeft.dx, closeTo(40, 1));
    });

    test('empty candidate list falls back', () {
      final result = svc.detectBest(const [], frame);
      expect(result.isFallback, isTrue);
    });
  });

  group('DocumentDetectionService.estimateFromEnergy', () {
    test('finds the central high-energy band as the document', () {
      // 20 rows/cols: background low energy, document band high energy.
      final rowEnergy = List<double>.generate(
          20, (i) => (i >= 4 && i <= 15) ? 100.0 : 5.0);
      final colEnergy = List<double>.generate(
          20, (i) => (i >= 3 && i <= 16) ? 100.0 : 5.0);
      final result =
          svc.estimateFromEnergy(rowEnergy, colEnergy, const Size(200, 200));
      expect(result.isFallback, isFalse);
      // top = 4/20*200 = 40 ; bottom = 16/20*200 = 160
      expect(result.corners.topLeft.dy, closeTo(40, 1));
      expect(result.corners.bottomRight.dy, closeTo(160, 1));
      // left = 3/20*200 = 30 ; right = 17/20*200 = 170
      expect(result.corners.topLeft.dx, closeTo(30, 1));
      expect(result.corners.bottomRight.dx, closeTo(170, 1));
    });

    test('flat (no edges) energy falls back', () {
      final flat = List<double>.filled(20, 0.0);
      final result = svc.estimateFromEnergy(flat, flat, const Size(200, 200));
      expect(result.isFallback, isTrue);
    });

    test('takes the largest contiguous band, ignoring small spikes', () {
      // A tiny spike near the start, the real document band in the middle.
      final energy = List<double>.generate(30, (i) {
        if (i == 1) return 100.0; // noise spike (length 1)
        if (i >= 10 && i <= 25) return 90.0; // document band (length 16)
        return 2.0;
      });
      final result = svc.estimateFromEnergy(energy, energy, const Size(300, 300));
      expect(result.isFallback, isFalse);
      // Band 10..25 -> top = 10/30*300 = 100
      expect(result.corners.topLeft.dy, closeTo(100, 1));
    });
  });
}
