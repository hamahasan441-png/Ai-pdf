import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/grid_snap_service.dart';

void main() {
  const svc = GridSnapService();

  group('GridSnapService (Phase 20)', () {
    test('snapValue rounds to the nearest multiple', () {
      expect(svc.snapValue(0.11, 0.05), closeTo(0.10, 1e-9));
      expect(svc.snapValue(0.13, 0.05), closeTo(0.15, 1e-9));
      expect(svc.snapValue(0.125, 0.05), closeTo(0.15, 1e-9)); // .round() up
    });

    test('non-positive grid disables snapping', () {
      expect(svc.snapValue(0.37, 0), 0.37);
      expect(svc.snapValue(0.37, -1), 0.37);
    });

    test('snapPoint snaps both axes', () {
      final p = svc.snapPoint(const Offset(0.11, 0.28),
          gridX: 0.05, gridY: 0.1);
      expect(p.dx, closeTo(0.10, 1e-9));
      expect(p.dy, closeTo(0.30, 1e-9));
    });

    test('snapRect moves position but preserves size by default', () {
      final r = svc.snapRect(
        const Rect.fromLTWH(0.11, 0.09, 0.23, 0.17),
        gridX: 0.05,
        gridY: 0.05,
      );
      expect(r.left, closeTo(0.10, 1e-9));
      expect(r.top, closeTo(0.10, 1e-9));
      expect(r.width, closeTo(0.23, 1e-9)); // unchanged
      expect(r.height, closeTo(0.17, 1e-9));
    });

    test('snapRect with snapSize snaps dimensions too (min one cell)', () {
      final r = svc.snapRect(
        const Rect.fromLTWH(0.11, 0.09, 0.23, 0.01),
        gridX: 0.05,
        gridY: 0.05,
        snapSize: true,
      );
      expect(r.width, closeTo(0.25, 1e-9)); // 0.23 -> 0.25
      expect(r.height, closeTo(0.05, 1e-9)); // 0.01 -> rounds to 0, floored to a cell
    });

    test('snapNear only snaps within the threshold and reports guides', () {
      // Close to gridline 0.10 -> snaps, guide reported.
      final near = svc.snapNear(const Offset(0.105, 0.5),
          gridX: 0.05, gridY: 0.0, threshold: 0.01);
      expect(near.point.dx, closeTo(0.10, 1e-9));
      expect(near.guideX, closeTo(0.10, 1e-9));
      expect(near.guideY, isNull); // gridY disabled
      expect(near.snapped, isTrue);

      // Far from any line (midway) -> no snap.
      final far = svc.snapNear(const Offset(0.125, 0.5),
          gridX: 0.05, gridY: 0.0, threshold: 0.01);
      expect(far.point.dx, closeTo(0.125, 1e-9));
      expect(far.guideX, isNull);
      expect(far.snapped, isFalse);
    });
  });
}
