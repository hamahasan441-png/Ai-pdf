import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/page_number_badge.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

void main() {
  test('numbering writes one searchable badge per page and replaces the old ones', () {
    final layers = <int, PageLayer>{
      0: PageLayer()..items.add(TextAnnotation(Offset.zero, 'keep', const Color(0xFF000000), 0.02, false)),
      1: PageLayer()..items.add(pageNumberBadge(0, 9)),
    };

    expect(syncPageNumbers(layers, 3), 3);

    expect(layers[0]!.items.where((a) => a is TextAnnotation && (a as TextAnnotation).text == 'keep'), hasLength(1));
    expect(layers.keys, [0, 1, 2]);
    for (var i = 0; i < 3; i++) {
      final badges = layers[i]!.items.where(isPageNumberBadge).cast<TextAnnotation>().toList();
      expect(badges, hasLength(1));
      expect(badges.single.text, '${i + 1} / 3');
    }
  });

  test('a reorder rewrites numbers only when the document was already numbered', () {
    final plain = <int, PageLayer>{0: PageLayer(), 1: PageLayer()};
    expect(refreshPageNumbers(plain, 2), 0);
    expect(documentHasPageNumbers(plain), isFalse);

    final numbered = <int, PageLayer>{};
    syncPageNumbers(numbered, 2);
    final stale = numbered[0]!.items.where(isPageNumberBadge).first as TextAnnotation;
    stale.text = 'stale';
    expect(refreshPageNumbers(numbered, 2), 2);
    expect((numbered[0]!.items.single as TextAnnotation).text, '1 / 2');
    expect((numbered[1]!.items.single as TextAnnotation).text, '2 / 2');
  });
}
