import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/watermark_service.dart';

void main() {
  const svc = WatermarkService();

  group('WatermarkService (Phase 19)', () {
    test('single is one centred stamp with default angle/opacity', () {
      final plan = svc.single();
      expect(plan.positions, const [Offset(0.5, 0.5)]);
      expect(plan.angleDegrees, WatermarkService.defaultAngleDegrees);
      expect(plan.opacity, WatermarkService.defaultOpacity);
    });

    test('tiled without stagger lays a regular grid inset by half a step', () {
      final plan = svc.tiled(spacingX: 0.5, spacingY: 0.5, stagger: false);
      // xs: 0.25, 0.75 ; ys: 0.25, 0.75 => 4 points.
      expect(plan.count, 4);
      expect(
        plan.positions.contains(const Offset(0.25, 0.25)),
        isTrue,
      );
      expect(
        plan.positions.contains(const Offset(0.75, 0.75)),
        isTrue,
      );
    });

    test('all tiled positions fall strictly inside the page', () {
      final plan = svc.tiled(spacingX: 0.2, spacingY: 0.2, stagger: false);
      for (final p in plan.positions) {
        expect(p.dx > 0 && p.dx < 1, isTrue);
        expect(p.dy > 0 && p.dy < 1, isTrue);
      }
    });

    test('stagger shifts alternate rows to the right', () {
      final plan = svc.tiled(spacingX: 0.5, spacingY: 0.5, stagger: true);
      // Row 0 (y=0.25): x = 0.25, 0.75
      // Row 1 (y=0.75): x starts at 0.5 -> just 0.5 (next 1.0 is out)
      final row1 = plan.positions.where((p) => p.dy == 0.75).toList();
      expect(row1.length, 1);
      expect(row1.single.dx, closeTo(0.5, 1e-9));
    });

    test('smaller spacing yields more stamps', () {
      final coarse = svc.tiled(spacingX: 0.5, spacingY: 0.5, stagger: false);
      final fine = svc.tiled(spacingX: 0.2, spacingY: 0.2, stagger: false);
      expect(fine.count, greaterThan(coarse.count));
    });

    test('custom angle and opacity are carried through', () {
      final plan = svc.tiled(angleDegrees: 30, opacity: 0.4);
      expect(plan.angleDegrees, 30);
      expect(plan.opacity, 0.4);
    });
  });
}
