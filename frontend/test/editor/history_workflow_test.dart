import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/application/editor_controller.dart';
import 'package:ai_pdf/features/editor/data/annotation_persistence_service.dart';
import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/data/page_structure.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Open → edit text → change style → add mark → undo → redo → save → reopen,
/// run against the controller and the recovery file the editor screen uses.

String _snap(Map<int, PageLayer> layers) => jsonEncode(layersToJson(layers));

TextAnnotation _text(String s) =>
    TextAnnotation(const Offset(0.1, 0.1), s, Colors.black, 0.03, false);

ShapeAnnotation _box() =>
    ShapeAnnotation(ShapeType.rect, const Offset(0.2, 0.2), const Offset(0.4, 0.3), Colors.red, 2, false);

void main() {
  late Directory tmp;
  late AnnotationPersistenceService store;
  const source = '/storage/emulated/0/Download/contract.pdf';

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('history_workflow');
    store = AnnotationPersistenceService(documentsDirectory: () async => tmp);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test('edit, restyle, annotate, undo, redo, save and reopen', () async {
    final c = EditorController();
    c.beginOpenFile(fileName: 'contract.pdf', filePath: source);
    c.finishOpenFile(pageCount: 2);
    final layers = <int, PageLayer>{0: PageLayer()};
    final layer = layers[0]!;
    expect(c.canUndo, isFalse);
    expect(c.canRedo, isFalse);

    final t = _text('Invoice 2024');
    c.pushAnnotation(layer, t);
    final afterText = _snap(layers);

    c.beginEdit([t], label: 'Style');
    t
      ..bold = true
      ..color = Colors.blue
      ..size = 0.05;
    c.commitEdit(layer);
    final afterStyle = _snap(layers);
    expect(afterStyle, isNot(afterText));

    final box = _box();
    c.pushAnnotation(layer, box);
    final afterBox = _snap(layers);

    c.undo(layer);
    expect(_snap(layers), afterStyle, reason: 'undo removes the box');
    c.undo(layer);
    expect(_snap(layers), afterText, reason: 'undo restores the old style');
    expect(t.bold, isFalse);

    c.redo(layer);
    expect(_snap(layers), afterStyle);
    c.redo(layer);
    expect(_snap(layers), afterBox);
    expect(c.canRedo, isFalse);

    // A new edit after an undo drops the redo branch.
    c.undo(layer);
    expect(c.canRedo, isTrue);
    c.pushAnnotation(layer, _text('note'));
    expect(c.canRedo, isFalse);
    expect(layer.items.whereType<ShapeAnnotation>(), isEmpty);
    final saved = _snap(layers);

    await store.save(filePath: source, layers: layers);
    expect(c.state.hasUnsavedChanges, isTrue);

    // "Close" and reopen: a fresh controller and fresh layers.
    final reopened = await store.loadChecked(source);
    expect(reopened.corrupt, isFalse);
    expect(_snap(reopened.layers), saved);
    // Loading twice does not duplicate marks.
    expect(_snap((await store.loadChecked(source)).layers), saved);
    final c2 = EditorController()..beginOpenFile(fileName: 'contract.pdf', filePath: source);
    expect(c2.canUndo, isFalse, reason: 'history is per session');
  });

  test('empty history: undo and redo do nothing and do not mark dirty', () {
    final c = EditorController()..finishOpenFile(pageCount: 1);
    final layer = PageLayer();
    c.undo(layer);
    c.redo(layer);
    expect(layer.items, isEmpty);
    expect(c.state.hasUnsavedChanges, isFalse);
  });

  test('repeated undo/redo cycles end where they started', () {
    final c = EditorController()..finishOpenFile(pageCount: 1);
    final layers = {0: PageLayer()};
    for (var i = 0; i < 5; i++) {
      c.pushAnnotation(layers[0]!, _text('t$i'));
    }
    final full = _snap(layers);
    for (var round = 0; round < 3; round++) {
      for (var i = 0; i < 5; i++) {
        c.undo(layers[0]!);
      }
      expect(layers[0]!.items, isEmpty);
      for (var i = 0; i < 5; i++) {
        c.redo(layers[0]!);
      }
      expect(_snap(layers), full);
    }
  });

  test('edits on one page do not touch another page', () {
    final c = EditorController()..finishOpenFile(pageCount: 2);
    final layers = {0: PageLayer(), 1: PageLayer()};
    c.pushAnnotation(layers[0]!, _text('page one'));
    c.setCurrentPage(1);
    c.pushAnnotation(layers[1]!, _text('page two'));
    c.undo(layers[1]!);
    expect(layers[1]!.items, isEmpty);
    expect(layers[0]!.items, hasLength(1));
    c.setCurrentPage(0);
    expect(c.canUndo, isTrue);
  });

  test('a mark added to a page that is not current is undone on that page', () {
    final c = EditorController()..finishOpenFile(pageCount: 3);
    final layers = {0: PageLayer(), 2: PageLayer()};
    // The user moved to page 0 while page 2's redaction was uploading.
    c.pushAnnotation(layers[2]!, _box(), page: 2);
    expect(c.canUndo, isFalse, reason: 'page 0 has no step');
    c.setCurrentPage(2);
    expect(c.canUndo, isTrue);
    c.undo(layers[2]!);
    expect(layers[2]!.items, isEmpty);
  });

  group('history follows pages', () {
    test('after deleting a page, undo acts on the page that moved up', () {
      final c = EditorController()..finishOpenFile(pageCount: 3);
      final layers = {0: PageLayer(), 1: PageLayer(), 2: PageLayer()};
      final onTwo = _text('on page 2');
      final onThree = _text('on page 3');
      c.setCurrentPage(1);
      c.pushAnnotation(layers[1]!, onTwo);
      c.deleteSelected(layers[1]!, onTwo); // undo would bring it back
      c.setCurrentPage(2);
      c.pushAnnotation(layers[2]!, onThree);

      // Delete page 0, as the screen does.
      final shifted = PageSourceMap.afterDelete(layers, 0, 3);
      layers
        ..clear()
        ..addAll(shifted);
      c.shiftHistories((h) => PageSourceMap.afterDelete(h, 0, 3));
      c.setPageCount(2);

      // Old page 2 is now page 0; its undo restores its own text.
      c.setCurrentPage(0);
      c.undo(layers[0]!);
      expect(layers[0]!.items, [onTwo]);
      expect(layers[1]!.items, [onThree], reason: 'old page 3 is untouched');

      // Old page 3 is now page 1 and keeps its own history.
      c.setCurrentPage(1);
      c.undo(layers[1]!);
      expect(layers[1]!.items, isEmpty);
      expect(layers[0]!.items, [onTwo]);
    });

    test('after inserting a page, the new page has no history', () {
      final c = EditorController()..finishOpenFile(pageCount: 1);
      final layers = {0: PageLayer()};
      final t = _text('first');
      c.pushAnnotation(layers[0]!, t);
      final shifted = PageSourceMap.afterInsert(layers, 0, 1);
      layers
        ..clear()
        ..addAll(shifted)
        ..[0] = PageLayer();
      c.shiftHistories((h) => PageSourceMap.afterInsert(h, 0, 1));
      c.setPageCount(2);
      c.setCurrentPage(0);
      expect(c.canUndo, isFalse);
      c.setCurrentPage(1);
      c.undo(layers[1]!);
      expect(layers[1]!.items, isEmpty);
    });
  });

  group('recovery file keeps the page structure', () {
    test('structure round-trips with the marks', () async {
      final layers = {0: PageLayer()..items.add(_text('after delete'))};
      const structure = SavedPageStructure(sources: [1, -1, 2], quarterTurns: {0: 1, 2: 3});
      await store.save(filePath: source, layers: layers, structure: structure);
      final back = await store.loadChecked(source);
      expect(back.structure!.sources, [1, -1, 2]);
      expect(back.structure!.quarterTurns, {0: 1, 2: 3});
      expect(back.structure!.fits(3, back.layers.keys), isTrue);
      expect(back.structure!.isIdentity, isFalse);
    });

    test('files written before structure existed still load', () async {
      final file = File('${tmp.path}/annotations/legacy.json');
      file.parent.createSync(recursive: true);
      final layers = {0: PageLayer()..items.add(_text('old'))};
      await store.save(filePath: source, layers: layers);
      final back = await store.loadChecked(source);
      expect(back.structure, isNull);
      expect(back.layers[0]!.items, hasLength(1));
    });

    test('a structure that does not fit the opened PDF is refused', () {
      const s = SavedPageStructure(sources: [0, 1, 4]);
      expect(s.fits(3, const [0]), isFalse, reason: 'PDF page 4 does not exist');
      expect(const SavedPageStructure(sources: [0, 1]).fits(5, const [0, 2]), isFalse,
          reason: 'marks on position 2 but only 2 positions');
      expect(const SavedPageStructure(sources: [0, 1]).fits(2, const [1]), isTrue);
    });

    test('malformed structure is treated as a corrupt file', () async {
      final layers = {0: PageLayer()..items.add(_text('x'))};
      await store.save(filePath: source, layers: layers);
      final path = tmp.listSync(recursive: true).whereType<File>().single.path;
      final json = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      json['structure'] = {'sources': ['a']};
      File(path).writeAsStringSync(jsonEncode(json));
      final back = await store.loadChecked(source);
      expect(back.corrupt, isTrue);
      expect(back.layers, isEmpty);
      expect(File('$path.corrupt').existsSync(), isTrue);
    });

    test('quarantine moves the file aside', () async {
      await store.save(filePath: source, layers: {0: PageLayer()..items.add(_text('x'))});
      await store.quarantine(source);
      expect(await store.hasSavedState(source), isFalse);
      expect((await store.loadChecked(source)).layers, isEmpty);
    });

    for (final bad in [
      null,
      'x',
      {'sources': []},
      {'sources': [0, -2]},
      {'sources': [0], 'turns': {'3': 1}},
      {'sources': [0], 'turns': 'x'},
    ]) {
      test('fromJson rejects $bad', () {
        expect(SavedPageStructure.fromJson(bad), isNull);
      });
    }
  });
}
