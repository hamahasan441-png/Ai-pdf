import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/object_arrange.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

void main() {
  ShapeAnnotation box() => ShapeAnnotation(
        ShapeType.rect,
        const Offset(0.1, 0.2),
        const Offset(0.3, 0.4),
        const Color(0xFF000000),
        0.004,
      );

  test('nudge steps a mark and refuses a locked one', () {
    final shape = box();
    expect(nudgeAnnotation(shape, const Offset(fineNudge, 0)), isTrue);
    expect(shape.start.dx, closeTo(0.1 + fineNudge, 0.0001));
    shape.locked = true;
    expect(nudgeAnnotation(shape, const Offset(coarseNudge, 0)), isFalse);
    expect(shape.start.dx, closeTo(0.1 + fineNudge, 0.0001));
    expect(nudgeAnnotation(box(), Offset.zero), isFalse);
  });

  test('one object centres on the page', () {
    final shape = box();
    expect(centerAnnotationOnPage(shape), isTrue);
    expect(shape.bounds.center.dx, closeTo(0.5, 0.001));
    expect(shape.bounds.center.dy, closeTo(0.5, 0.001));

    final locked = box()..locked = true;
    final before = locked.bounds.center;
    expect(centerAnnotationOnPage(locked), isFalse);
    expect(locked.bounds.center, before);
  });
}
