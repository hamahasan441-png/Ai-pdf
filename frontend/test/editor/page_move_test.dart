import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/page_structure.dart';

void main() {
  test('moving a page re-keys per-page data like the page list moves', () {
    for (var n = 1; n <= 5; n++) {
      for (var from = 0; from < n; from++) {
        for (var to = 0; to < n; to++) {
          final pages = PageSourceMap(n)..move(from, to);
          final data = {for (var i = 0; i < n; i++) i: 'page $i'};
          final moved = PageSourceMap.afterMove(data, from, to);
          expect(moved.length, n);
          for (var i = 0; i < n; i++) {
            expect(moved[i], 'page ${pages.sources[i]}', reason: 'n=$n $from→$to at $i');
          }
        }
      }
    }
  });

  test('a moved page lands where it was dropped; sparse maps keep their gaps', () {
    expect((PageSourceMap(3)..move(0, 1)).sources, [1, 0, 2]);
    expect((PageSourceMap(4)..move(3, 0)).sources, [3, 0, 1, 2]);
    expect(PageSourceMap.afterMove({0: 'a', 3: 'd'}, 0, 2), {2: 'a', 3: 'd'});
    expect((PageSourceMap(2)..move(0, 5)).sources, [0, 1], reason: 'out of range is ignored');
  });
}
