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

    test('a shared prefix and suffix are preserved around the changed middle', () {
      // The LCS now runs on the trimmed middle only; the result must be the
      // same reading order as a plain diff would give.
      final old = ['h1', 'h2', 'old-a', 'old-b', 'f1', 'f2'];
      final new_ = ['h1', 'h2', 'new-a', 'new-b', 'f1', 'f2'];
      final segs = svc.diffLines(old.join('\n'), new_.join('\n'));
      expect(segs, const [
        DiffSegment(DiffKind.unchanged, 'h1'),
        DiffSegment(DiffKind.unchanged, 'h2'),
        DiffSegment(DiffKind.removed, 'old-a'),
        DiffSegment(DiffKind.removed, 'old-b'),
        DiffSegment(DiffKind.added, 'new-a'),
        DiffSegment(DiffKind.added, 'new-b'),
        DiffSegment(DiffKind.unchanged, 'f1'),
        DiffSegment(DiffKind.unchanged, 'f2'),
      ]);
    });

    test('an oversized diff degrades to paired blocks instead of exploding memory', () {
      // 2100 x 2100 changed lines = 4.41M cells > the 4M cap, so the service
      // reports removed-then-added blocks. The output is still complete and
      // correctly ordered; it just does not claim pairing.
      final old = [for (var i = 0; i < 2100; i++) 'old $i'];
      final new_ = [for (var i = 0; i < 2100; i++) 'new $i'];
      final segs = svc.diffLines(old.join('\n'), new_.join('\n'));
      final stats = svc.stats(segs);
      expect(stats.removed, 2100);
      expect(stats.added, 2100);
      expect(stats.unchanged, 0);
      // Every removal comes before every addition.
      final lastRemoved = segs.lastIndexWhere((s) => s.kind == DiffKind.removed);
      final firstAdded = segs.indexWhere((s) => s.kind == DiffKind.added);
      expect(lastRemoved, lessThan(firstAdded));
    });

    test('identical large documents stay cheap and unchanged', () {
      // A 2100-line identical document trims to nothing in the middle — the
      // cap must not turn pure-identical docs into removed/added noise.
      final text = [for (var i = 0; i < 2100; i++) 'same $i'].join('\n');
      final segs = svc.diffLines(text, text);
      expect(svc.stats(segs).identical, isTrue);
    });
  });
}
