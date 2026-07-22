import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/scanner/data/scan_stability_detector.dart';

void main() {
  const svc = ScanStabilityDetector();

  List<int> checkerboard(int w, int h) => [
        for (var y = 0; y < h; y++)
          for (var x = 0; x < w; x++) ((x + y) % 2 == 0) ? 0 : 255,
      ];

  group('ScanStabilityDetector.blurScore', () {
    test('a flat image has ~zero sharpness (fully blurred)', () {
      final flat = List<int>.filled(8 * 8, 128);
      expect(svc.blurScore(flat, 8, 8), closeTo(0.0, 1e-9));
    });

    test('a high-frequency checkerboard is very sharp', () {
      final sharp = checkerboard(8, 8);
      final flat = List<int>.filled(8 * 8, 128);
      expect(svc.blurScore(sharp, 8, 8),
          greaterThan(svc.blurScore(flat, 8, 8)));
      expect(svc.blurScore(sharp, 8, 8),
          greaterThan(ScanStabilityDetector.defaultSharpnessThreshold));
    });

    test('degenerate sizes return 0', () {
      expect(svc.blurScore(const [1, 2], 2, 1), 0.0);
    });
  });

  group('ScanStabilityDetector.motionScore', () {
    test('identical frames have zero motion', () {
      final a = checkerboard(6, 6);
      expect(svc.motionScore(a, a), 0.0);
    });

    test('very different frames have high motion', () {
      final a = List<int>.filled(36, 0);
      final b = List<int>.filled(36, 255);
      expect(svc.motionScore(a, b), 255.0);
    });

    test('mismatched sizes are treated as moving (infinity)', () {
      expect(svc.motionScore(const [1, 2, 3], const [1, 2]),
          double.infinity);
    });
  });

  group('ScanStabilityDetector.evaluate', () {
    test('sharp + still frame is ready to capture', () {
      final frame = checkerboard(10, 10);
      final prev = checkerboard(10, 10); // identical -> no motion
      final r = svc.evaluate(frame, prev, 10, 10);
      expect(r.sharpEnough, isTrue);
      expect(r.still, isTrue);
      expect(r.readyToCapture, isTrue);
    });

    test('first frame (no previous) is never ready (motion = infinity)', () {
      final frame = checkerboard(10, 10);
      final r = svc.evaluate(frame, null, 10, 10);
      expect(r.motion, double.infinity);
      expect(r.still, isFalse);
      expect(r.readyToCapture, isFalse);
    });

    test('blurry frame is not ready even when still', () {
      final flat = List<int>.filled(100, 130);
      final prev = List<int>.filled(100, 130);
      final r = svc.evaluate(flat, prev, 10, 10);
      expect(r.sharpEnough, isFalse);
      expect(r.readyToCapture, isFalse);
    });

    test('moving frame is not ready even when sharp', () {
      final a = checkerboard(10, 10);
      // Shift the checkerboard by inverting -> large per-pixel diff.
      final b = [for (final v in a) 255 - v];
      final r = svc.evaluate(a, b, 10, 10);
      expect(r.sharpEnough, isTrue);
      expect(r.still, isFalse);
      expect(r.readyToCapture, isFalse);
    });
  });
}
