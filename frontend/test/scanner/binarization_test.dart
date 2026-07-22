import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/scanner/data/scan_binarization_service.dart';

void main() {
  const svc = ScanBinarizationService();

  group('ScanBinarizationService.sauvola', () {
    test('marks a thin dark stroke black and the paper white', () {
      // 8x8 bright paper (220) with a thin dark vertical stroke at column x=4
      // (value 20) — the case Sauvola is designed for (text on paper).
      const w = 8, h = 8;
      final gray = <int>[];
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          gray.add(x == 4 ? 20 : 220);
        }
      }
      final out = svc.sauvola(gray, w, h, window: 5);
      // A pixel on the dark stroke (x=4, y=3) -> black; paper far away -> white.
      expect(out[3 * w + 4], 0); // stroke pixel
      expect(out[0], 255); // paper corner
    });

    test('a uniform image has no local contrast -> all background (white)', () {
      const w = 6, h = 6;
      final gray = List<int>.filled(w * h, 200);
      final out = svc.sauvola(gray, w, h, window: 5);
      expect(out.every((v) => v == 255), isTrue);
    });

    test('output length matches input and is strictly 0 or 255', () {
      const w = 10, h = 4;
      final gray = List<int>.generate(w * h, (i) => (i * 37) % 256);
      final out = svc.sauvola(gray, w, h, window: 7);
      expect(out.length, w * h);
      expect(out.every((v) => v == 0 || v == 255), isTrue);
    });

    test('rejects a mismatched buffer length', () {
      expect(() => svc.sauvola([1, 2, 3], 2, 2), throwsArgumentError);
    });
  });

  group('ScanBinarizationService.otsuThreshold', () {
    test('finds a threshold between two well-separated modes', () {
      // Half the pixels at 40, half at 210.
      final gray = <int>[
        ...List<int>.filled(100, 40),
        ...List<int>.filled(100, 210),
      ];
      final t = svc.otsuThreshold(gray);
      expect(t, greaterThan(40));
      expect(t, lessThan(210));
    });

    test('applyThreshold produces a clean split', () {
      final gray = <int>[10, 60, 130, 200, 250];
      final out = svc.applyThreshold(gray, 128);
      expect(out, [0, 0, 0, 255, 255]);
    });

    test('empty input returns a safe mid threshold', () {
      expect(svc.otsuThreshold(const []), 127);
    });
  });
}
