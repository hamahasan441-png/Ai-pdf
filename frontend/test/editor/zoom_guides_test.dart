import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/tile_zoom_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/annotation_bounds_service.dart';
import 'package:ai_pdf/features/editor/domain/services/rotation_math.dart';
import 'package:ai_pdf/features/editor/domain/services/selection_service.dart';

void main() {
  group('TileZoomService planner (Phase 6)', () {
    const svc = TileZoomService();

    test('needsHighRes activates past the threshold', () {
      expect(svc.needsHighRes(1.0), isFalse);
      expect(svc.needsHighRes(2.0), isTrue);
    });

    test('targetMaxEdge scales with zoom but is clamped to the hard cap', () {
      expect(svc.targetMaxEdge(baseMaxEdge: 2400, zoom: 1.0, hardCap: 4800), 2400);
      expect(svc.targetMaxEdge(baseMaxEdge: 2400, zoom: 1.5, hardCap: 4800), 3600);
      expect(svc.targetMaxEdge(baseMaxEdge: 2400, zoom: 2.0, hardCap: 4800), 4800);
      // Deep zoom never exceeds the memory-bounded hard cap.
      expect(svc.targetMaxEdge(baseMaxEdge: 2400, zoom: 5.0, hardCap: 4800), 4800);
    });
  });

  group('Object-to-object snapping (Phase 7)', () {
    const selection = SelectionService();
    const bounds = AnnotationBoundsService();

    test('snaps a moved object to another object\'s edge', () {
      final target = ShapeAnnotation(
          ShapeType.rect, const Offset(0.5, 0.05), const Offset(0.9, 0.15), Colors.black, 2);
      final moving = ShapeAnnotation(
          ShapeType.rect, const Offset(0.505, 0.6), const Offset(0.6, 0.7), Colors.black, 2);

      final guides = selection.snapSelected(moving, bounds, others: [target]);
      expect(guides.guideX, closeTo(0.5, 1e-9));
      expect(bounds.boundsOf(moving).left, closeTo(0.5, 1e-9));
      expect(guides.guideY, isNull);
    });

    test('no others → falls back to page-guide behaviour (no crash)', () {
      final a = ShapeAnnotation(
          ShapeType.rect, const Offset(0.1, 0.1), const Offset(0.2, 0.2), Colors.black, 2);
      final guides = selection.snapSelected(a, bounds);
      expect(guides, isNotNull);
    });
  });

  group('Rotation handle math (Phase 7)', () {
    test('maps pointer direction to object rotation', () {
      const center = Offset(100, 100);
      expect(rotationForHandle(center, const Offset(100, 50)), closeTo(0.0, 1e-9)); // up
      expect(rotationForHandle(center, const Offset(150, 100)), closeTo(-math.pi / 2, 1e-9)); // right
      expect(rotationForHandle(center, const Offset(100, 150)), closeTo(-math.pi, 1e-9)); // down
    });
  });
}
