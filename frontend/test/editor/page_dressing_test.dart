import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/page_dressing.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

void main() {
  test('a watermark is faint searchable text, centred, and replaces the old one', () {
    final mark = pageWatermark('  DRAFT  ');
    expect(mark.text, 'DRAFT');
    expect(mark.rotation, 0);
    expect(mark.opacity, closeTo(0.22, 0.001));
    expect(mark.bounds.center.dx, closeTo(0.5, 0.001));
    expect(mark.bounds.center.dy, closeTo(0.5, 0.001));
    expect(isPageWatermark(mark), isTrue);

    final layers = <int, PageLayer>{
      0: PageLayer()..items.add(TextAnnotation(Offset.zero, 'keep', const Color(0xFF000000), 0.02, false)),
      1: PageLayer()..items.add(pageWatermark('OLD')),
    };
    expect(syncWatermarks(layers, 3, 'CONFIDENTIAL'), 3);
    expect((layers[0]!.items.first as TextAnnotation).text, 'keep');
    for (var i = 0; i < 3; i++) {
      final marks = layers[i]!.items.where(isPageWatermark).cast<TextAnnotation>().toList();
      expect(marks, hasLength(1));
      expect(marks.single.text, 'CONFIDENTIAL');
    }
  });

  test('a blank watermark clears it, and a header is separate furniture', () {
    final layers = <int, PageLayer>{};
    syncWatermarks(layers, 2, 'COPY');
    syncHeaders(layers, 2, 'Pdoczy');
    expect(clearMarkedText(layers, pageWatermarkKey), 2);
    expect(layers[0]!.items.where(isPageWatermark), isEmpty);
    expect(layers[0]!.items.where(isPageHeader).cast<TextAnnotation>().single.text, 'Pdoczy');
    expect(syncHeaders(layers, 2, '   '), greaterThan(0));
    expect(layers[0]!.items, isEmpty);
  });

  test('moving pages rewrites the words only when furniture is already there', () {
    final plain = <int, PageLayer>{0: PageLayer(), 1: PageLayer()};
    expect(refreshPageDressing(plain, 2), isFalse);

    final dressed = <int, PageLayer>{};
    syncWatermarks(dressed, 2, 'PAID');
    syncHeaders(dressed, 2, 'Contract');
    (dressed[1]!.items.firstWhere(isPageWatermark) as TextAnnotation).text = 'stale';
    expect(refreshPageDressing(dressed, 3), isTrue);
    expect(dressed.keys, containsAll([0, 1, 2]));
    for (var i = 0; i < 3; i++) {
      expect((dressed[i]!.items.singleWhere(isPageWatermark) as TextAnnotation).text, 'PAID');
      expect((dressed[i]!.items.singleWhere(isPageHeader) as TextAnnotation).text, 'Contract');
    }
  });
}
