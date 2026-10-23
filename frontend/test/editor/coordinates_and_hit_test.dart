import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/editor_canvas_interaction_service.dart';
import 'package:ai_pdf/features/editor/data/editor_hit_test_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/services/page_coordinate_transform.dart';

const hit = EditorHitTestService();

PageLayer layerOf(List<EditorAnnotation> items) => PageLayer()..items.addAll(items);

void main() {
  group('gesture normalization', () {
    const svc = EditorCanvasInteractionService();

    test('maps a pointer to 0..1 on the page', () {
      expect(svc.normalize(const Offset(100, 200), const Size(400, 800)), const Offset(0.25, 0.25));
    });

    test('clamps a pointer outside the page to its edge', () {
      expect(svc.normalize(const Offset(-50, 900), const Size(400, 800)), const Offset(0, 1));
    });

    test('a zero, negative or infinite canvas gives no position', () {
      for (final size in const [Size.zero, Size(0, 800), Size(400, -1), Size(double.infinity, 800)]) {
        expect(svc.normalize(const Offset(10, 10), size), isNull, reason: '$size');
      }
    });

    test('a non-finite pointer gives no position', () {
      expect(svc.normalize(const Offset(double.nan, 1), const Size(400, 800)), isNull);
      expect(svc.normalize(const Offset(1, double.infinity), const Size(400, 800)), isNull);
    });
  });

  group('hit testing', () {
    test('text is hit anywhere in its box, not only near its anchor', () {
      final t = TextAnnotation(const Offset(0.1, 0.1), 'A long line of text', Colors.black, 0.03, false);
      final box = t.bounds;
      expect(hit.hitTest(layerOf([t]), Offset(box.right - 0.005, box.center.dy)), same(t),
          reason: 'end of the line');
      expect(hit.hitTest(layerOf([t]), const Offset(0.05, 0.05)), isNull, reason: 'empty space above-left');
    });

    test('a multi-line text box is as tall as its lines', () {
      final one = TextAnnotation(const Offset(0.1, 0.1), 'abc', Colors.black, 0.03, false);
      final three = TextAnnotation(const Offset(0.1, 0.1), 'abc\nabcdef\nab', Colors.black, 0.03, false);
      expect(three.bounds.height, closeTo(one.bounds.height * 3, 1e-9));
      expect(three.bounds.width, closeTo(one.bounds.width * 2, 1e-9), reason: 'longest line');
      expect(hit.hitTest(layerOf([three]), Offset(0.12, three.bounds.bottom - 0.01)), same(three));
    });

    test('a diagonal line takes taps only near the line', () {
      final line = ShapeAnnotation(ShapeType.line, const Offset(0.1, 0.1), const Offset(0.9, 0.9), Colors.red, 2);
      expect(hit.hitTest(layerOf([line]), const Offset(0.5, 0.505)), same(line));
      expect(hit.hitTest(layerOf([line]), const Offset(0.8, 0.2)), isNull, reason: 'inside the bbox, far from the line');
    });

    test('a long stroke does not steal taps from a mark underneath', () {
      final box = ShapeAnnotation(ShapeType.rect, const Offset(0.6, 0.1), const Offset(0.8, 0.3), Colors.blue, 2);
      final stroke = StrokeAnnotation(const [Offset(0.1, 0.1), Offset(0.9, 0.9)], Colors.black, 3, false);
      final layer = layerOf([box, stroke]); // stroke drawn on top
      expect(hit.hitTest(layer, const Offset(0.7, 0.2)), same(box));
      expect(hit.hitTest(layer, const Offset(0.5, 0.5)), same(stroke));
    });

    test('the topmost visible, unlocked mark wins', () {
      final bottom = ShapeAnnotation(ShapeType.rect, const Offset(0.1, 0.1), const Offset(0.5, 0.5), Colors.red, 2);
      final top = ShapeAnnotation(ShapeType.rect, const Offset(0.2, 0.2), const Offset(0.4, 0.4), Colors.blue, 2);
      expect(hit.hitTest(layerOf([bottom, top]), const Offset(0.3, 0.3)), same(top));
      top.visible = false;
      expect(hit.hitTest(layerOf([bottom, top]), const Offset(0.3, 0.3)), same(bottom));
      top
        ..visible = true
        ..locked = true;
      expect(hit.hitTest(layerOf([bottom, top]), const Offset(0.3, 0.3)), same(bottom));
    });

    test('a non-finite point hits nothing', () {
      final t = TextAnnotation(const Offset(0.1, 0.1), 'x', Colors.black, 0.03, false);
      expect(hit.hitTest(layerOf([t]), const Offset(double.nan, 0.1)), isNull);
    });
  });

  group('zoom/pan transforms', () {
    final rng = math.Random(42);

    Matrix4 randomViewer() {
      final m = Matrix4.identity()
        ..translate(rng.nextDouble() * 800 - 400, rng.nextDouble() * 800 - 400)
        ..rotateZ(rng.nextInt(4) * math.pi / 2)
        ..scale(0.5 + rng.nextDouble() * 7.5);
      return m;
    }

    test('map then invert returns the point, also after 100 round trips', () {
      for (var i = 0; i < 200; i++) {
        final m = randomViewer();
        final p = Offset(rng.nextDouble() * 1000, rng.nextDouble() * 1000);
        var q = p;
        for (var k = 0; k < 100; k++) {
          q = PageCoordinateTransform.invertPoint(m, PageCoordinateTransform.mapPoint(m, q));
        }
        expect((q - p).distance, lessThan(1e-6), reason: 'matrix $i');
      }
    });

    test('screen → page → screen is stable with a viewport offset', () {
      for (var i = 0; i < 100; i++) {
        final t = PageCoordinateTransform(
          canvasSize: const Size(411, 581),
          viewportOffset: Offset(rng.nextDouble() * 100, rng.nextDouble() * 200),
          zoomMatrix: randomViewer(),
        );
        final norm = Offset(rng.nextDouble(), rng.nextDouble());
        final back = t.screenToPdf(t.pdfOffsetToScreen(norm));
        expect((back - norm).distance, lessThan(1e-9));
      }
    });

    test('the inline editor origin follows the mark at any zoom', () {
      // The inline editor is placed with zoomedPagePoint; the canvas maps the
      // same mark through the viewer matrix. Both must agree.
      const pageLeft = 12.0;
      const pageTop = 30.0;
      const pageSize = Size(400, 566);
      const norm = Offset(0.3, 0.7);
      for (final scale in [0.5, 1.0, 2.0, 5.0]) {
        final m = Matrix4.identity()
          ..translate(-120.0, 40.0)
          ..scale(scale);
        final origin = PageCoordinateTransform.zoomedPagePoint(
          norm: norm,
          pageLeft: pageLeft,
          pageTop: pageTop,
          pageSize: pageSize,
          zoom: m,
        );
        final expected = Offset(
          -120 + scale * (pageLeft + norm.dx * pageSize.width),
          40 + scale * (pageTop + norm.dy * pageSize.height),
        );
        expect((origin - expected).distance, lessThan(1e-9), reason: 'scale $scale');
        expect(PageCoordinateTransform.uniformScale(m), closeTo(scale, 1e-12));
      }
    });

    test('a singular matrix does not produce NaN', () {
      final m = Matrix4.zero();
      final p = PageCoordinateTransform.invertPoint(m, const Offset(5, 5));
      expect(p.dx.isFinite && p.dy.isFinite, isTrue);
      const t = PageCoordinateTransform(canvasSize: Size.zero);
      final n = t.canvasToPdf(const Offset(3, 3));
      expect(n.dx.isFinite && n.dy.isFinite, isTrue);
    });
  });
}
