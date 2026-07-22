import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/scanner/domain/entities/document_corners.dart';
import 'package:ai_pdf/features/scanner/domain/services/corner_ordering_service.dart';
import 'package:ai_pdf/features/scanner/domain/services/perspective_transform_service.dart';

void main() {
  group('DocumentCorners', () {
    test('full frame has correct edges, area and convexity', () {
      final c = DocumentCorners.fullFrame(const Size(100, 200));
      expect(c.topEdge, 100);
      expect(c.leftEdge, 200);
      expect(c.estimatedWidth, 100);
      expect(c.estimatedHeight, 200);
      expect(c.area, 20000);
      expect(c.isConvex, isTrue);
      expect(c.aspectRatio, closeTo(0.5, 1e-9));
    });

    test('inset frame shrinks by the margin fraction', () {
      final c = DocumentCorners.insetFrame(const Size(100, 100), 0.1);
      expect(c.topLeft, const Offset(10, 10));
      expect(c.bottomRight, const Offset(90, 90));
    });

    test('a self-intersecting quad is not convex', () {
      const c = DocumentCorners(
        topLeft: Offset(0, 0),
        topRight: Offset(10, 10), // swapped to create a bowtie
        bottomRight: Offset(10, 0),
        bottomLeft: Offset(0, 10),
      );
      expect(c.isConvex, isFalse);
    });

    test('withCorner replaces only the targeted corner', () {
      final c = DocumentCorners.fullFrame(const Size(10, 10));
      final moved = c.withCorner(2, const Offset(8, 9));
      expect(moved.bottomRight, const Offset(8, 9));
      expect(moved.topLeft, c.topLeft);
    });
  });

  group('CornerOrderingService', () {
    const svc = CornerOrderingService();

    test('orders shuffled points into TL/TR/BR/BL', () {
      final ordered = svc.order(const [
        Offset(10, 90), // BL
        Offset(90, 10), // TR
        Offset(10, 10), // TL
        Offset(90, 90), // BR
      ]);
      expect(ordered.topLeft, const Offset(10, 10));
      expect(ordered.topRight, const Offset(90, 10));
      expect(ordered.bottomRight, const Offset(90, 90));
      expect(ordered.bottomLeft, const Offset(10, 90));
      expect(ordered.isConvex, isTrue);
    });

    test('handles a slightly rotated quad and stays convex', () {
      final ordered = svc.order(const [
        Offset(30, 8),
        Offset(92, 34),
        Offset(66, 94),
        Offset(6, 66),
      ]);
      expect(ordered.isConvex, isTrue);
      // sum/diff assignment: TL=min(x+y), BR=max(x+y), TR=min(y-x), BL=max(y-x)
      expect(ordered.topLeft, const Offset(30, 8));
      expect(ordered.topRight, const Offset(92, 34));
      expect(ordered.bottomRight, const Offset(66, 94));
      expect(ordered.bottomLeft, const Offset(6, 66));
    });

    test('rejects non-4-point input', () {
      expect(() => svc.order(const [Offset(0, 0)]), throwsArgumentError);
    });

    test('orderFromContour picks the extreme points of many', () {
      final ordered = svc.orderFromContour(const [
        Offset(10, 10), Offset(50, 5), Offset(90, 12), // top edge
        Offset(92, 50), Offset(88, 90), // right + BR
        Offset(45, 95), Offset(8, 88), Offset(5, 45), // bottom + left
      ]);
      expect(ordered.topLeft.dx, lessThan(20));
      expect(ordered.topLeft.dy, lessThan(20));
      expect(ordered.bottomRight.dx, greaterThan(80));
      expect(ordered.bottomRight.dy, greaterThan(80));
    });
  });

  group('PerspectiveTransformService', () {
    const svc = PerspectiveTransformService();

    test('outputSize derives from the longer edges, capped', () {
      final c = DocumentCorners.fullFrame(const Size(1000, 1500));
      final size = svc.outputSize(c, maxDimension: 600);
      // Longest side 1500 -> capped to 600, aspect preserved (2:3).
      expect(size.height, 600);
      expect(size.width, 400);
    });

    test('identity: mapping a rect to itself leaves points unchanged', () {
      final c = DocumentCorners.fullFrame(const Size(100, 100));
      final h = svc.srcToDest(c, const Size(100, 100));
      final p = h.map(const Offset(25, 75));
      expect(p.dx, closeTo(25, 1e-6));
      expect(p.dy, closeTo(75, 1e-6));
    });

    test('destToSrc maps rectangle corners exactly onto the source quad', () {
      const c = DocumentCorners(
        topLeft: Offset(20, 30),
        topRight: Offset(180, 10),
        bottomRight: Offset(190, 260),
        bottomLeft: Offset(5, 240),
      );
      const dst = Size(200, 250);
      final h = svc.destToSrc(c, dst);

      final tl = h.map(const Offset(0, 0));
      final tr = h.map(const Offset(200, 0));
      final br = h.map(const Offset(200, 250));
      final bl = h.map(const Offset(0, 250));

      expect(tl.dx, closeTo(20, 1e-4));
      expect(tl.dy, closeTo(30, 1e-4));
      expect(tr.dx, closeTo(180, 1e-4));
      expect(tr.dy, closeTo(10, 1e-4));
      expect(br.dx, closeTo(190, 1e-4));
      expect(br.dy, closeTo(260, 1e-4));
      expect(bl.dx, closeTo(5, 1e-4));
      expect(bl.dy, closeTo(240, 1e-4));
    });

    test('the centre of the dst maps inside the source quad bbox', () {
      const c = DocumentCorners(
        topLeft: Offset(20, 30),
        topRight: Offset(180, 10),
        bottomRight: Offset(190, 260),
        bottomLeft: Offset(5, 240),
      );
      const dst = Size(200, 250);
      final h = svc.destToSrc(c, dst);
      final centre = h.map(const Offset(100, 125));
      final bbox = c.boundingBox;
      expect(bbox.contains(centre), isTrue);
    });

    test('srcToDest and destToSrc are inverses (round-trip)', () {
      const c = DocumentCorners(
        topLeft: Offset(12, 22),
        topRight: Offset(210, 8),
        bottomRight: Offset(240, 300),
        bottomLeft: Offset(2, 280),
      );
      const dst = Size(220, 300);
      final fwd = svc.srcToDest(c, dst);
      final inv = svc.destToSrc(c, dst);

      const srcPoint = Offset(80, 120);
      final roundTrip = inv.map(fwd.map(srcPoint));
      expect(roundTrip.dx, closeTo(80, 1e-3));
      expect(roundTrip.dy, closeTo(120, 1e-3));
    });
  });
}
