import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/application/editor_controller.dart';
import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/history/editor_command.dart';
import 'package:ai_pdf/features/editor/domain/history/editor_history.dart';

void main() {
  group('Transformable DOM contract', () {
    test('base props default to sane values', () {
      final t = TextAnnotation(const Offset(0.1, 0.2), 'hi', Colors.black, 0.05, false);
      expect(t.opacity, 1.0);
      expect(t.locked, false);
      expect(t.visible, true);
      expect(t.zIndex, 0);
      expect(t.metadata, isEmpty);
    });

    test('text bounds / translate / scaleTo behave as before', () {
      final t = TextAnnotation(const Offset(0.1, 0.1), 'hello', Colors.black, 0.05, false);
      final b = t.bounds;
      expect(b.left, closeTo(0.1, 1e-9));
      expect(b.top, closeTo(0.1, 1e-9));

      t.translate(const Offset(0.2, 0.1));
      expect(t.pos.dx, closeTo(0.3, 1e-9));
      expect(t.pos.dy, closeTo(0.2, 1e-9));

      // Translation is clamped to the text upper bound (0.98).
      t.translate(const Offset(5, 5));
      expect(t.pos.dx, closeTo(0.98, 1e-9));
      expect(t.pos.dy, closeTo(0.98, 1e-9));
    });

    test('shape translate + scaleTo remap endpoints', () {
      final s = ShapeAnnotation(
          ShapeType.rect, const Offset(0.1, 0.1), const Offset(0.3, 0.2), Colors.red, 2);
      s.translate(const Offset(0.1, 0.0));
      expect(s.start.dx, closeTo(0.2, 1e-9));
      expect(s.end.dx, closeTo(0.4, 1e-9));

      s.scaleTo(const Rect.fromLTRB(0.0, 0.0, 0.5, 0.5));
      expect(s.bounds.left, closeTo(0.0, 1e-9));
      expect(s.bounds.right, closeTo(0.5, 1e-9));
    });

    test('clone mints a new id but clone(id:) preserves it; base props copied', () {
      final s = ShapeAnnotation(
          ShapeType.rect, const Offset(0.1, 0.1), const Offset(0.3, 0.2), Colors.red, 2, true)
        ..opacity = 0.4
        ..locked = true;
      final dup = s.clone(shift: 0.05);
      expect(dup.id, isNot(s.id));
      expect(dup.filled, isTrue);
      expect(dup.opacity, 0.4);
      expect(dup.locked, isTrue);
      expect((dup as ShapeAnnotation).start.dx, closeTo(0.15, 1e-9));

      final memento = s.clone(id: s.id);
      expect(memento.id, s.id);
    });

    test('restoreFrom copies mutable state back in place', () {
      final t = TextAnnotation(const Offset(0.1, 0.1), 'a', Colors.black, 0.05, false);
      final before = t.clone(id: t.id);
      t
        ..text = 'changed'
        ..size = 0.09
        ..pos = const Offset(0.5, 0.5);
      t.restoreFrom(before);
      expect(t.text, 'a');
      expect(t.size, 0.05);
      expect(t.pos.dx, closeTo(0.1, 1e-9));
    });
  });

  group('EditorHistory + commands', () {
    test('RestoreStateCommand round-trips undo/redo', () {
      final layer = PageLayer();
      final t = TextAnnotation(const Offset(0.1, 0.1), 'x', Colors.black, 0.05, false);
      layer.items.add(t);

      final before = t.clone(id: t.id);
      t.translate(const Offset(0.3, 0.0));
      final after = t.clone(id: t.id);
      final cmd = RestoreStateCommand([t], [before], [after], 'Move');

      final history = EditorHistory();
      history.push(cmd, layer);
      expect(t.pos.dx, closeTo(0.4, 1e-9));

      history.undo(layer);
      expect(t.pos.dx, closeTo(0.1, 1e-9));
      expect(history.canRedo, isTrue);

      history.redo(layer);
      expect(t.pos.dx, closeTo(0.4, 1e-9));
    });

    test('ReorderCommand restores paint order', () {
      final a = TextAnnotation(const Offset(0, 0), 'a', Colors.black, 0.05, false);
      final b = TextAnnotation(const Offset(0, 0), 'b', Colors.black, 0.05, false);
      final layer = PageLayer()..items.addAll([a, b]);

      final beforeOrder = List<EditorAnnotation>.of(layer.items);
      layer.items
        ..remove(a)
        ..add(a); // bring a to front → [b, a]
      final afterOrder = List<EditorAnnotation>.of(layer.items);

      final history = EditorHistory();
      history.push(ReorderCommand(beforeOrder, afterOrder, 'Front'), layer);
      expect(layer.items.last, same(a));
      history.undo(layer);
      expect(layer.items.first, same(a));
    });

    test('pushing a new command clears the redo stack', () {
      final layer = PageLayer();
      final t = TextAnnotation(const Offset(0, 0), 'x', Colors.black, 0.05, false);
      final history = EditorHistory();
      history.push(AddCommand(t), layer);
      history.undo(layer);
      expect(history.canRedo, isTrue);
      history.push(AddCommand(t), layer);
      expect(history.canRedo, isFalse);
    });
  });

  group('EditorController transaction API', () {
    test('move via beginEdit/commitEdit is a single undoable step', () {
      final c = EditorController();
      final layer = PageLayer();
      final t = TextAnnotation(const Offset(0.1, 0.1), 'x', Colors.black, 0.05, false);

      c.pushAnnotation(layer, t); // AddCommand
      expect(c.canUndo, isTrue);

      c.beginEdit([t], label: 'Move');
      t.translate(const Offset(0.2, 0.0)); // simulate live drag
      c.commitEdit(layer);
      expect(t.pos.dx, closeTo(0.3, 1e-9));

      c.undo(layer); // undo move
      expect(t.pos.dx, closeTo(0.1, 1e-9));
      c.undo(layer); // undo add
      expect(layer.items, isEmpty);
      expect(c.canUndo, isFalse);
    });

    test('commitEdit with no change pushes nothing', () {
      final c = EditorController();
      final layer = PageLayer();
      final t = TextAnnotation(const Offset(0.1, 0.1), 'x', Colors.black, 0.05, false);
      c.pushAnnotation(layer, t);

      c.beginEdit([t]);
      c.commitEdit(layer); // no mutation → no command
      c.undo(layer); // should undo the ADD directly
      expect(layer.items, isEmpty);
      expect(c.canUndo, isFalse);
    });

    test('commitEdit(force:true) records a bounds-neutral style change', () {
      final c = EditorController();
      final layer = PageLayer();
      final t = TextAnnotation(const Offset(0.1, 0.1), 'x', Colors.black, 0.05, false);
      c.pushAnnotation(layer, t);

      c.beginEdit([t], label: 'Text colour');
      t.color = Colors.red;
      c.commitEdit(layer, force: true);

      c.undo(layer);
      expect(t.color, Colors.black);
    });
  });

  group('Serialization base props', () {
    test('round-trips opacity / locked / visible / zIndex / metadata', () {
      final s = ShapeAnnotation(
          ShapeType.rect, const Offset(0.1, 0.1), const Offset(0.3, 0.2), Colors.red, 2, true)
        ..opacity = 0.3
        ..locked = true
        ..visible = false
        ..zIndex = 5
        ..metadata['source'] = 'ai';

      final restored = annotationFromJson(annotationToJson(s))! as ShapeAnnotation;
      expect(restored.opacity, 0.3);
      expect(restored.locked, isTrue);
      expect(restored.visible, isFalse);
      expect(restored.zIndex, 5);
      expect(restored.metadata['source'], 'ai');
      expect(restored.filled, isTrue);
    });

    test('legacy JSON without base props falls back to defaults', () {
      // Simulates a file written by an older build (no base-prop keys).
      final legacy = <String, dynamic>{
        'type': 'text',
        'id': 'legacy-1',
        'posX': 0.2,
        'posY': 0.3,
        'text': 'old',
        'color': Colors.black.value,
        'size': 0.04,
        'bold': false,
      };
      final a = annotationFromJson(legacy)!;
      expect(a.opacity, 1.0);
      expect(a.locked, isFalse);
      expect(a.visible, isTrue);
      expect(a.zIndex, 0);
      expect(a.id, 'legacy-1');
    });
  });
}
