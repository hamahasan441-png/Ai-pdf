import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/application/editor_controller.dart';
import 'package:ai_pdf/features/editor/application/editor_state.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

void main() {
  group('EditorState.copyWith', () {
    const full = EditorState(filePath: '/a.pdf', fileName: 'a.pdf', error: 'boom', pageCount: 3);

    test('omitted nullable fields are kept', () {
      final next = full.copyWith(loading: true);
      expect(next.filePath, '/a.pdf');
      expect(next.fileName, 'a.pdf');
      expect(next.error, 'boom');
      expect(next.pageCount, 3);
      expect(next.loading, isTrue);
    });

    test('an explicit null clears the field', () {
      expect(full.copyWith(error: null).error, isNull);
      expect(full.copyWith(filePath: null).filePath, isNull);
      expect(full.copyWith(fileName: null).fileName, isNull);
      expect(full.copyWith(error: null).filePath, '/a.pdf', reason: 'other fields stay');
    });

    test('a value replaces the field', () {
      expect(full.copyWith(error: 'new').error, 'new');
      expect(full.copyWith(filePath: '/b.pdf').filePath, '/b.pdf');
    });
  });

  group('EditorController lifecycle', () {
    late EditorController c;
    setUp(() => c = EditorController());
    tearDown(() => c.dispose());

    test('a successful export clears the previous export error', () {
      c.beginExport();
      c.finishExport(error: 'Export failed: disk full');
      expect(c.state.error, 'Export failed: disk full');
      c.beginExport();
      expect(c.state.error, isNull, reason: 'a new attempt starts clean');
      expect(c.state.exporting, isTrue);
      c.finishExport();
      expect(c.state.error, isNull);
      expect(c.state.exporting, isFalse);
      expect(c.state.loading, isFalse);
    });

    test('consecutive exports each report their own outcome', () {
      for (final outcome in ['first failed', null, 'third failed', null]) {
        c.beginExport();
        c.finishExport(error: outcome);
        expect(c.state.error, outcome);
      }
    });

    test('a failed open then a successful open leaves no stale error', () {
      c.beginOpenFile(fileName: 'bad.pdf', filePath: '/bad.pdf');
      c.failOpenFile('Could not open file');
      expect(c.state.error, 'Could not open file');
      expect(c.state.loading, isFalse);
      c.beginOpenFile(fileName: 'good.pdf', filePath: '/good.pdf');
      expect(c.state.error, isNull);
      c.finishOpenFile(pageCount: 4);
      expect(c.state.error, isNull);
      expect(c.state.filePath, '/good.pdf');
      expect(c.state.fileName, 'good.pdf');
      expect(c.state.pageCount, 4);
    });

    test('finishOpenFile clears an error set while the file was loading', () {
      c.beginOpenFile(fileName: 'a.pdf', filePath: '/a.pdf');
      c.setError('Rotate failed');
      c.finishOpenFile(pageCount: 1);
      expect(c.state.error, isNull);
    });

    test('setError(null) clears the error', () {
      c.setError('x');
      c.setError(null);
      expect(c.state.error, isNull);
    });

    test('opening a new file resets dirty flag, page and history', () {
      c.beginOpenFile(fileName: 'a.pdf', filePath: '/a.pdf');
      c.finishOpenFile(pageCount: 5, currentPage: 3);
      final layer = PageLayer();
      c.pushAnnotation(layer, TextAnnotation(Offset.zero, 'a', Colors.black, 0.03, false));
      expect(c.canUndo, isTrue);
      expect(c.state.hasUnsavedChanges, isTrue);

      c.beginOpenFile(fileName: 'b.pdf', filePath: '/b.pdf');
      expect(c.canUndo, isFalse, reason: 'history does not cross documents');
      expect(c.state.hasUnsavedChanges, isFalse);
      expect(c.state.currentPage, 0);
      expect(c.state.filePath, '/b.pdf');
    });

    test('an edit begun on one document cannot commit into the next', () {
      c.beginOpenFile(fileName: 'a.pdf', filePath: '/a.pdf');
      c.finishOpenFile(pageCount: 1);
      final t = TextAnnotation(Offset.zero, 'a', Colors.black, 0.03, false);
      final layerA = PageLayer()..items.add(t);
      c.beginEdit([t], label: 'Move');
      t.pos = const Offset(0.5, 0.5);

      c.beginOpenFile(fileName: 'b.pdf', filePath: '/b.pdf');
      c.finishOpenFile(pageCount: 1);
      c.commitEdit(PageLayer(), force: true);
      expect(c.canUndo, isFalse);
      expect(layerA.items.single, same(t));
    });
  });
}
