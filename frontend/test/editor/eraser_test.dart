import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/application/editor_controller.dart';
import 'package:ai_pdf/features/editor/data/editor_hit_test_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

void main() {
  test('eraser hits the ink under the finger, not a distant stroke', () {
    final near = StrokeAnnotation(
      const [Offset(0.1, 0.5), Offset(0.9, 0.5)],
      Colors.black,
      2,
      false,
    );
    final far = StrokeAnnotation(
      const [Offset(0.1, 0.1), Offset(0.2, 0.1)],
      Colors.black,
      2,
      false,
    );
    final layer = PageLayer()
      ..items.add(far)
      ..items.add(near);
    final hit = const EditorHitTestService().strokeNear(layer, const Offset(0.5, 0.5));
    expect(hit, same(near));
    expect(
      const EditorHitTestService().strokeNear(layer, const Offset(0.5, 0.9)),
      isNull,
    );
  });

  test('eraser removes ink and leaves other objects, and undo puts the ink back', () {
    final ink = StrokeAnnotation(
      const [Offset(0.0, 0.4), Offset(1.0, 0.4)],
      Colors.black,
      2,
      false,
    );
    final box = ShapeAnnotation(
      ShapeType.rect,
      const Offset(0.3, 0.3),
      const Offset(0.6, 0.6),
      Colors.red,
      1,
    );
    final layer = PageLayer()
      ..items.add(box)
      ..items.add(ink);
    final editor = EditorController();
    expect(editor.eraseStrokeAt(layer, const Offset(0.5, 0.4)), isTrue);
    expect(layer.strokes, isEmpty);
    expect(layer.shapes, hasLength(1));
    expect(editor.eraseStrokeAt(layer, const Offset(0.45, 0.45)), isFalse);
    editor.undo(layer);
    expect(layer.strokes, hasLength(1));
    expect(layer.items, hasLength(2));
  });

  test('a locked stroke is not erased', () {
    final ink = StrokeAnnotation(
      const [Offset(0.0, 0.2), Offset(1.0, 0.2)],
      Colors.black,
      2,
      false,
    )..locked = true;
    final layer = PageLayer()..items.add(ink);
    expect(EditorController().eraseStrokeAt(layer, const Offset(0.5, 0.2)), isFalse);
    expect(layer.strokes, hasLength(1));
  });
}
