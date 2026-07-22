import 'package:flutter_test/flutter_test.dart';

import 'package:ai_pdf/features/editor/domain/services/document_outline_service.dart';

void main() {
  const svc = DocumentOutlineService();

  // 1 Introduction (p0)
  //   1.1 Background (p1)
  //   1.2 Scope (p2)
  // 2 Methods (p3)
  //   2.1 Data (p4)
  //     2.1.1 Sources (p5)
  final headings = const [
    OutlineHeading(title: 'Introduction', page: 0, level: 1),
    OutlineHeading(title: 'Background', page: 1, level: 2),
    OutlineHeading(title: 'Scope', page: 2, level: 2),
    OutlineHeading(title: 'Methods', page: 3, level: 1),
    OutlineHeading(title: 'Data', page: 4, level: 2),
    OutlineHeading(title: 'Sources', page: 5, level: 3),
  ];

  group('DocumentOutlineService (Phase 15)', () {
    test('build nests headings by level', () {
      final roots = svc.build(headings);
      expect(roots.length, 2);
      expect(roots[0].title, 'Introduction');
      expect(roots[0].children.map((c) => c.title), ['Background', 'Scope']);
      expect(roots[1].title, 'Methods');
      expect(roots[1].children.single.title, 'Data');
      expect(roots[1].children.single.children.single.title, 'Sources');
    });

    test('flattenVisible respects collapse state', () {
      final roots = svc.build(headings);
      // All expanded => all 6 rows, with depth increasing.
      var rows = svc.flattenVisible(roots);
      expect(rows.length, 6);
      expect(rows.map((r) => r.depth).toList(), [0, 1, 1, 0, 1, 2]);

      // Collapse "Methods" => hides Data + Sources (2 rows drop).
      svc.toggle(roots[1]);
      rows = svc.flattenVisible(roots);
      expect(rows.map((r) => r.node.title),
          ['Introduction', 'Background', 'Scope', 'Methods']);
    });

    test('expandAll / collapseAll toggle the whole tree', () {
      final roots = svc.build(headings);
      svc.collapseAll(roots);
      expect(svc.flattenVisible(roots).length, 2); // only the two roots
      svc.expandAll(roots);
      expect(svc.flattenVisible(roots).length, 6);
    });

    test('flattenAll ignores collapse state', () {
      final roots = svc.build(headings);
      svc.collapseAll(roots);
      expect(svc.flattenAll(roots).length, 6);
    });

    test('nearestForPage returns the section a page belongs to', () {
      final roots = svc.build(headings);
      expect(svc.nearestForPage(roots, 0)!.title, 'Introduction');
      expect(svc.nearestForPage(roots, 2)!.title, 'Scope');
      expect(svc.nearestForPage(roots, 6)!.title, 'Sources'); // last section
      expect(svc.nearestForPage(roots, 5)!.title, 'Sources');
    });

    test('a deeper-first heading is still rooted; levels are normalised', () {
      final roots = svc.build(const [
        OutlineHeading(title: 'Orphan', page: 0, level: 3),
        OutlineHeading(title: 'Top', page: 1, level: 1),
        OutlineHeading(title: 'Sub', page: 2, level: 2),
      ]);
      expect(roots.map((r) => r.title), ['Orphan', 'Top']);
      expect(roots[1].children.single.title, 'Sub');
    });

    test('empty input yields an empty outline', () {
      expect(svc.build(const []), isEmpty);
      expect(svc.nearestForPage(const [], 0), isNull);
    });
  });
}
