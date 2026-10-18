import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/application/editor_controller.dart';
import 'package:ai_pdf/features/editor/application/editor_layer_controller.dart';
import 'package:ai_pdf/features/editor/data/editor_canvas_interaction_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/services/annotation_bounds_service.dart';

void main() {
  late TextAnnotation text;
  late ShapeAnnotation box;
  late ShapeAnnotation redaction;
  late StrokeAnnotation ink;
  late PageLayer page;

  setUp(() {
    text = TextAnnotation(const Offset(0.1, 0.1), 'Hello', Colors.black, 0.03, false);
    box = ShapeAnnotation(ShapeType.rect, const Offset(0.2, 0.2), const Offset(0.4, 0.4), Colors.red, 2);
    redaction = ShapeAnnotation(ShapeType.rect, const Offset(0.5, 0.5), const Offset(0.7, 0.6), Colors.black, 1, true)
      ..metadata[visualCoverKey] = true;
    ink = StrokeAnnotation(const [Offset(0.1, 0.8), Offset(0.3, 0.9)], Colors.blue, 3, false);
    page = PageLayer()..items.addAll([text, box, redaction, ink]);
  });

  test('rows list the kinds on the page with their counts', () {
    final rows = EditorLayerController.layersOf(page);
    expect([for (final r in rows) (r.kind, r.itemCount)], [('text', 1), ('shape', 1), ('stroke', 1)],
        reason: 'the redaction cover is not a layer');
    expect(EditorLayerController.layersOf(null), isEmpty);
  });

  test('hiding a kind hides those marks only, and never a redaction cover', () {
    EditorLayerController.toggleVisibility(page, 'shape');
    expect(box.visible, isFalse);
    expect(redaction.visible, isTrue);
    expect(text.visible, isTrue);
    expect(EditorLayerController.layersOf(page)[1].visible, isFalse);

    EditorLayerController.setAllVisible(page, false);
    expect([text.visible, box.visible, ink.visible, redaction.visible], [false, false, false, true]);
    EditorLayerController.setAllVisible(page, true);
    expect([text.visible, box.visible, ink.visible], [true, true, true]);
  });

  test('a partly hidden kind is shown again by its toggle', () {
    final second = TextAnnotation(const Offset(0.5, 0.1), 'Two', Colors.black, 0.03, false)..visible = false;
    page.items.add(second);
    expect(EditorLayerController.layersOf(page).first.visible, isFalse);
    EditorLayerController.toggleVisibility(page, 'text');
    expect([text.visible, second.visible], [true, true]);
  });

  test('a layer change is one undoable step', () {
    final c = EditorController();
    addTearDown(c.dispose);
    final items = EditorLayerController.targets(page, null);
    c.beginEdit(items, label: 'Layers');
    EditorLayerController.toggleLock(page, 'text');
    EditorLayerController.toggleVisibility(page, 'stroke');
    c.commitEdit(page);
    expect([text.locked, ink.visible], [true, false]);
    c.undo(page);
    expect([text.locked, ink.visible], [false, true]);
    expect(c.canUndo, isFalse);
  });

  test('a box selection skips hidden and locked marks', () {
    box.locked = true;
    ink.visible = false;
    final picked = const EditorCanvasInteractionService().marqueeSelection(
      items: page.items,
      marqueeStart: Offset.zero,
      marqueeEnd: const Offset(1, 1),
      bounds: const AnnotationBoundsService(),
    );
    expect(picked, {text, redaction});
  });
}
