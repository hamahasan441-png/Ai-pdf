import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/bates_numbering_service.dart';

void main() {
  const svc = BatesNumberingService();

  group('BatesNumberingService (Phase 22)', () {
    test('generates one ascending, zero-padded stamp per page', () {
      final stamps = svc.generate(
        3,
        const BatesConfig(prefix: 'ABC-', padding: 6, start: 1),
      );
      expect(stamps.length, 3);
      expect(stamps.map((s) => s.label),
          ['ABC-000001', 'ABC-000002', 'ABC-000003']);
      expect(stamps.map((s) => s.pageIndex), [0, 1, 2]);
    });

    test('honours start, step, prefix and suffix', () {
      final stamps = svc.generate(
        3,
        const BatesConfig(
          prefix: 'DOC',
          suffix: '-C',
          start: 100,
          step: 5,
          padding: 4,
        ),
      );
      expect(stamps.map((s) => s.label),
          ['DOC0100-C', 'DOC0105-C', 'DOC0110-C']);
      expect(stamps.map((s) => s.number), [100, 105, 110]);
    });

    test('padding <= 0 disables zero-padding', () {
      expect(svc.format(42, const BatesConfig(padding: 0)), '42');
      expect(svc.format(42, const BatesConfig(padding: -1, prefix: 'X')), 'X42');
    });

    test('number longer than padding is not truncated', () {
      expect(svc.format(1234567, const BatesConfig(padding: 4)), '1234567');
    });

    test('generateForOrder supports subsets / custom orderings', () {
      final stamps = svc.generateForOrder(
        [4, 2, 0],
        const BatesConfig(prefix: 'P', padding: 3, start: 1),
      );
      expect(stamps.map((s) => s.pageIndex), [4, 2, 0]);
      expect(stamps.map((s) => s.label), ['P001', 'P002', 'P003']);
    });

    test('empty document yields no stamps', () {
      expect(svc.generate(0, const BatesConfig()), isEmpty);
    });

    test('default position is bottom-right', () {
      expect(const BatesConfig().position, BatesPosition.bottomRight);
    });
  });
}
