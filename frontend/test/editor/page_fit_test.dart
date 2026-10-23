import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/page_coordinate_transform.dart';
import 'package:ai_pdf/features/editor/domain/services/page_fit.dart';

void main() {
  test('a landscape page keeps its own aspect inside a tall viewport', () {
    final box = PageFit.box(maxWidth: 400, maxHeight: 800, aspect: 1.5);
    expect(box.width, 400);
    expect(box.height, closeTo(400 / 1.5, 0.001));
    expect(box.width / box.height, closeTo(1.5, 0.001));
  });

  test('a wide viewport letterboxes a portrait page', () {
    final box = PageFit.box(maxWidth: 1000, maxHeight: 500, aspect: 0.5);
    expect(box.height, 500);
    expect(box.width, 250);
    expect(box.left, 375);
    expect(box.top, 0);
  });

  test('a square page stays square', () {
    final box = PageFit.box(maxWidth: 300, maxHeight: 400, aspect: 1);
    expect(box.width, 300);
    expect(box.height, 300);
    expect(box.top, 50);
  });

  test('a bad aspect falls back to A4 portrait instead of collapsing', () {
    final box = PageFit.box(maxWidth: 200, maxHeight: 400, aspect: 0);
    expect(box.width / box.height, closeTo(PageFit.a4PortraitAspect, 0.0001));
    expect(box.width, greaterThan(0));
  });

  test('zoom moves an overlay with the page instead of leaving it behind', () {
    const page = Size(100, 200);
    final identity = PageCoordinateTransform.zoomedPagePoint(
      norm: const Offset(0.5, 0.25),
      pageLeft: 20,
      pageTop: 10,
      pageSize: page,
      zoom: Matrix4.identity(),
    );
    expect(identity.dx, 70);
    expect(identity.dy, 60);

    final zoomed = PageCoordinateTransform.zoomedPagePoint(
      norm: const Offset(0.5, 0.25),
      pageLeft: 20,
      pageTop: 10,
      pageSize: page,
      zoom: Matrix4.identity()..scale(2.0)..translate(4.0, 5.0),
    );
    expect(zoomed.dx, closeTo(148, 0.001));
    expect(zoomed.dy, closeTo(130, 0.001));
  });

  test('zoom levels 1x 2x 3x and 5x stay on the page point', () {
    const page = Size(100, 200);
    const norm = Offset(0.25, 0.5);
    for (final scale in [1.0, 2.0, 3.0, 5.0]) {
      final zoom = Matrix4.identity()..scale(scale);
      final screen = PageCoordinateTransform.zoomedPagePoint(
        norm: norm,
        pageLeft: 0,
        pageTop: 0,
        pageSize: page,
        zoom: zoom,
      );
      expect(screen.dx, closeTo(25 * scale, 0.001));
      expect(screen.dy, closeTo(100 * scale, 0.001));
      final back = PageCoordinateTransform.invertPoint(zoom, screen);
      expect(back.dx, closeTo(25, 0.001));
      expect(back.dy, closeTo(100, 0.001));
    }
  });

  test('a rotated matrix round-trips and is not the diagonal-only formula', () {
    final zoom = Matrix4.rotationZ(math.pi / 2);
    const local = Offset(10, 0);
    final mapped = PageCoordinateTransform.mapPoint(zoom, local);
    expect(mapped.dx, closeTo(0, 0.001));
    expect(mapped.dy, closeTo(10, 0.001));
    final back = PageCoordinateTransform.invertPoint(zoom, mapped);
    expect(back.dx, closeTo(10, 0.001));
    expect(back.dy, closeTo(0, 0.001));

    final transform = PageCoordinateTransform(
      canvasSize: const Size(200, 400),
      viewportOffset: const Offset(8, 12),
      zoomMatrix: zoom,
    );
    const norm = Offset(0.3, 0.4);
    final screen = transform.pdfOffsetToScreen(norm);
    final recovered = transform.screenToPdf(screen);
    expect(recovered.dx, closeTo(norm.dx, 1e-6));
    expect(recovered.dy, closeTo(norm.dy, 1e-6));
  });

  test('pan in each direction moves the overlay by that translation', () {
    const page = Size(80, 80);
    for (final pan in const [
      Offset(30, 0),
      Offset(-20, 0),
      Offset(0, 15),
      Offset(0, -12),
      Offset(-4, 9),
    ]) {
      final zoom = Matrix4.identity()..translate(pan.dx, pan.dy);
      final p = PageCoordinateTransform.zoomedPagePoint(
        norm: const Offset(0, 0),
        pageLeft: 10,
        pageTop: 20,
        pageSize: page,
        zoom: zoom,
      );
      expect(p.dx, closeTo(10 + pan.dx, 0.001));
      expect(p.dy, closeTo(20 + pan.dy, 0.001));
    }
  });
}
