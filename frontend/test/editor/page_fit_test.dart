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
}
