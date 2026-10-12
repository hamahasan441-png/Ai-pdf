import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/page_reorder_service.dart';
import 'package:ai_pdf/features/editor/data/page_structure.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

void main() {
  test('deleting the first page keeps the later PDF page numbers', () {
    final plan = PageSourceMap(3)..removeAt(0);
    expect(plan.sources, [1, 2]);
    final turns = PageSourceMap.afterDelete({1: 2}, 0, 3);
    expect(turns[0], 2);
  });

  test('a blank insert is not a source page, and a duplicate points at the same page', () {
    final plan = PageSourceMap(2)
      ..insertBlank(1)
      ..duplicate(0);
    expect(plan.sources, [0, 0, -1, 1]);
  });

  test('duplicating a page copies its marks instead of leaving a blank layer', () {
    final layer = PageLayer()
      ..items.add(ShapeAnnotation(
        ShapeType.rect,
        const Offset(0.1, 0.1),
        const Offset(0.4, 0.4),
        Colors.black,
        1,
      ));
    final layers = {0: layer};
    const PageReorderService().duplicatePage(
      index: 0,
      pageCache: {0: Uint8List.fromList([1, 2, 3])},
      layers: layers,
      pageCount: 1,
    );
    expect(layers[1]?.shapes, hasLength(1));
    expect(identical(layers[0]!.shapes.single, layers[1]!.shapes.single), isFalse);
  });
}
