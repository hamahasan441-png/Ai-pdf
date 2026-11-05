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

  test('a header has three zones, and page tokens follow the page count', () {
    final layers = <int, PageLayer>{};
    applyRunningEdge(
      layers,
      2,
      RunningEdge.header,
      const RunningEdgeDraft(left: 'L', center: '{page} / {pages}', right: 'R'),
    );

    final page0 = layers[0]!.items.whereType<TextAnnotation>().toList();
    expect(page0, hasLength(3));
    final left = page0.singleWhere((t) => t.text == 'L');
    final center = page0.singleWhere((t) => t.text == '1 / 2');
    final right = page0.singleWhere((t) => t.text == 'R');
    expect(left.pos.dx, 0.04);
    expect(left.textAlign, TextAlign.left);
    expect(center.pos.dx, 0.34);
    expect(center.textAlign, TextAlign.center);
    expect(right.pos.dx, 0.68);
    expect(right.textAlign, TextAlign.right);
    expect(left.pos.dy, 0.018);
    expect(left.pos.dx + left.width!, lessThan(center.pos.dx));
    expect(center.pos.dx + center.width!, lessThan(right.pos.dx));

    expect(refreshPageDressing(layers, 4), isTrue);
    final last = layers[3]!.items.whereType<TextAnnotation>().singleWhere((t) => t.textAlign == TextAlign.center);
    expect(last.text, '4 / 4');
    expect(readRunningEdge(layers, RunningEdge.header).center, '{page} / {pages}');
  });

  test('Bates skips the cover, pads, and does not remove a watermark', () {
    final layers = <int, PageLayer>{};
    syncWatermarks(layers, 3, 'DRAFT');
    final written = syncRunningLine(layers, 3, batesLine('CASE-', start: 7, digits: 4, skipFirst: true));
    expect(written, 2);

    final cover = layers[0]!.items.where(isRunningLine).cast<TextAnnotation>().single;
    expect(cover.visible, isFalse);
    expect(cover.text, isEmpty);
    expect(layers[0]!.items.where(isPageWatermark), hasLength(1));

    expect((layers[1]!.items.singleWhere(isRunningLine) as TextAnnotation).text, 'CASE-0007');
    expect((layers[2]!.items.singleWhere(isRunningLine) as TextAnnotation).text, 'CASE-0008');
    expect((layers[1]!.items.singleWhere(isRunningLine) as TextAnnotation).pos.dy, greaterThan(0.9));

    expect(refreshPageDressing(layers, 4), isTrue);
    expect((layers[3]!.items.singleWhere(isRunningLine) as TextAnnotation).text, 'CASE-0009');
    expect(layers[0]!.items.where(isPageWatermark), hasLength(1));
  });

  test('clearing one zone leaves the others', () {
    final layers = <int, PageLayer>{};
    applyRunningEdge(
      layers,
      1,
      RunningEdge.footer,
      const RunningEdgeDraft(left: 'A', center: 'B', right: 'C'),
    );
    applyRunningEdge(
      layers,
      1,
      RunningEdge.footer,
      const RunningEdgeDraft(left: 'A', center: '', right: 'C'),
    );
    final texts = layers[0]!.items.whereType<TextAnnotation>().map((t) => t.text).toList();
    expect(texts, containsAll(['A', 'C']));
    expect(texts, isNot(contains('B')));
  });
}
