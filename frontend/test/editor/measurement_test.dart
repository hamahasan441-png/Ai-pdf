import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/measurement_service.dart';

void main() {
  const svc = MeasurementService();

  group('MeasurementService (Phase 21)', () {
    test('distance is Euclidean (3-4-5)', () {
      expect(svc.distance(const Offset(0, 0), const Offset(3, 4)), 5.0);
    });

    test('pathLength sums segments', () {
      final len = svc.pathLength(const [
        Offset(0, 0),
        Offset(3, 4), // +5
        Offset(3, 4 + 5), // +5
      ]);
      expect(len, 10.0);
    });

    test('polygonArea via shoelace (3x4 rectangle => 12)', () {
      final area = svc.polygonArea(const [
        Offset(0, 0),
        Offset(0, 4),
        Offset(3, 4),
        Offset(3, 0),
      ]);
      expect(area, 12.0);
    });

    test('polygon winding direction does not affect area sign', () {
      final cw = svc.polygonArea(const [
        Offset(0, 0),
        Offset(3, 0),
        Offset(3, 4),
        Offset(0, 4),
      ]);
      expect(cw, 12.0);
    });

    test('degenerate polygons have zero area', () {
      expect(svc.polygonArea(const [Offset(0, 0), Offset(1, 1)]), 0.0);
      expect(svc.polygonArea(const []), 0.0);
    });

    test('calibrate derives units-per-length and applies to distance', () {
      // A segment measured as 5 document units is really 10 cm.
      final cal = svc.calibrate(5, 10, 'cm');
      expect(cal.unitsPerLength, 2.0);
      expect(cal.unit, 'cm');
      expect(
        svc.realDistance(const Offset(0, 0), const Offset(3, 4), cal),
        10.0, // 5 * 2
      );
    });

    test('real area scales by the calibration factor squared', () {
      final cal = svc.calibrate(5, 10, 'cm'); // factor 2
      final square = const [
        Offset(0, 0),
        Offset(0, 4),
        Offset(3, 4),
        Offset(3, 0),
      ];
      expect(svc.realArea(square, cal), 48.0); // 12 * 2^2
    });

    test('calibrate rejects a non-positive measured length', () {
      expect(() => svc.calibrate(0, 10, 'cm'), throwsArgumentError);
    });

    test('format prints value with unit and fixed decimals', () {
      expect(svc.format(10.5, 'cm'), '10.50 cm');
      expect(svc.format(3.14159, 'm', decimals: 3), '3.142 m');
    });

    test('identity calibration leaves values unchanged', () {
      expect(
        svc.realDistance(const Offset(0, 0), const Offset(0, 7),
            MeasurementCalibration.identity),
        7.0,
      );
    });
  });
}
