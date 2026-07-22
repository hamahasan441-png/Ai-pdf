import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/page_range_service.dart';

void main() {
  const svc = PageRangeService();

  group('PageRangeService (Phase 18)', () {
    test('parses mixed singles and ranges to sorted 0-based indices', () {
      expect(svc.parse('1-3, 5, 8-10', 10), [0, 1, 2, 4, 7, 8, 9]);
    });

    test('ignores whitespace and tolerates empty tokens', () {
      expect(svc.parse(' 1 - 3 , , 5 ', 10), [0, 1, 2, 4]);
    });

    test('de-duplicates overlapping ranges', () {
      expect(svc.parse('1-3,2-4', 10), [0, 1, 2, 3]);
    });

    test('normalises a reversed range', () {
      expect(svc.parse('3-1', 10), [0, 1, 2]);
    });

    test('empty spec => empty list', () {
      expect(svc.parse('   ', 10), isEmpty);
    });

    test('throws on non-numeric or out-of-range tokens', () {
      expect(() => svc.parse('1-x', 10), throwsFormatException);
      expect(() => svc.parse('0', 10), throwsFormatException); // 1-based
      expect(() => svc.parse('11', 10), throwsFormatException);
    });

    test('tryParse returns null instead of throwing', () {
      expect(svc.tryParse('bad', 10), isNull);
      expect(svc.tryParse('2-4', 10), [1, 2, 3]);
    });

    test('format collapses consecutive indices into compact ranges', () {
      expect(svc.format([0, 1, 2, 4, 7, 8, 9]), '1-3, 5, 8-10');
      expect(svc.format([5]), '6');
      expect(svc.format([]), '');
    });

    test('format sorts and de-dupes its input', () {
      expect(svc.format([2, 0, 1, 1]), '1-3');
    });

    test('parse and format round-trip', () {
      const spec = '1-3, 5, 8-10';
      expect(svc.format(svc.parse(spec, 10)), spec);
    });

    test('invert returns the complement within the document', () {
      expect(svc.invert([0, 2, 4], 5), [1, 3]);
      expect(svc.invert([], 3), [0, 1, 2]);
    });
  });
}
