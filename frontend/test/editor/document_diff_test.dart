import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/data/document_diff_service.dart';

void main() {
  const svc = DocumentDiffService();

  group('DocumentDiffService (Phase 16)', () {
    test('identical documents are all unchanged', () {
      final segs = svc.diffLines('a\nb\nc', 'a\nb\nc');
      expect(segs.every((s) => s.kind == DiffKind.unchanged), isTrue);
      expect(svc.stats(segs).identical, isTrue);
    });

    test('a single inserted line shows as added, context preserved', () {
      final segs = svc.diffLines('a\nc', 'a\nb\nc');
      expect(segs, const [
        DiffSegment(DiffKind.unchanged, 'a'),
        DiffSegment(DiffKind.added, 'b'),
        DiffSegment(DiffKind.unchanged, 'c'),
      ]);
      final st = svc.stats(segs);
      expect(st.added, 1);
      expect(st.removed, 0);
      expect(st.identical, isFalse);
    });

    test('a removed line shows as removed', () {
      final segs = svc.diffLines('a\nb\nc', 'a\nc');
      expect(segs, const [
        DiffSegment(DiffKind.unchanged, 'a'),
        DiffSegment(DiffKind.removed, 'b'),
        DiffSegment(DiffKind.unchanged, 'c'),
      ]);
    });

    test('a replaced line is a removed+added pair', () {
      final segs = svc.diffLines('hello world', 'hello there');
      expect(segs.any((s) => s.kind == DiffKind.removed && s.text == 'hello world'),
          isTrue);
      expect(segs.any((s) => s.kind == DiffKind.added && s.text == 'hello there'),
          isTrue);
    });

    test('whitespace-only differences are ignored (trim + drop blanks)', () {
      final segs = svc.diffLines('a\n\n  b  ', '  a\nb\n');
      expect(segs.every((s) => s.kind == DiffKind.unchanged), isTrue);
      expect(svc.stats(segs).identical, isTrue);
    });

    test('word-level diff within a line', () {
      final segs = svc.diffWords('the quick brown fox', 'the slow brown fox');
      expect(segs, const [
        DiffSegment(DiffKind.unchanged, 'the'),
        DiffSegment(DiffKind.removed, 'quick'),
        DiffSegment(DiffKind.added, 'slow'),
        DiffSegment(DiffKind.unchanged, 'brown'),
        DiffSegment(DiffKind.unchanged, 'fox'),
      ]);
    });

    test('empty old document => everything added; empty new => removed', () {
      final added = svc.diffLines('', 'x\ny');
      expect(added.every((s) => s.kind == DiffKind.added), isTrue);
      expect(added.length, 2);

      final removed = svc.diffLines('x\ny', '');
      expect(removed.every((s) => s.kind == DiffKind.removed), isTrue);
      expect(removed.length, 2);
    });
  });
}
