import 'package:flutter_test/flutter_test.dart';

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
}
