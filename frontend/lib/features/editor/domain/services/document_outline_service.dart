/// A flat heading extracted from a document (native bookmark or AI-detected).
///
/// [level] is 1-based (1 = top-level heading). [page] is the zero-based page
/// the heading points to.
class OutlineHeading {
  final String title;
  final int page;
  final int level;

  const OutlineHeading({
    required this.title,
    required this.page,
    this.level = 1,
  });
}

/// A node in the hierarchical document outline / mind-map (Phase 15).
class OutlineNode {
  final String title;
  final int page;
  final int level;
  final List<OutlineNode> children;

  /// UI state — whether this node's children are shown. Defaults to expanded.
  bool expanded;

  OutlineNode({
    required this.title,
    required this.page,
    required this.level,
    List<OutlineNode>? children,
    this.expanded = true,
  }) : children = children ?? <OutlineNode>[];

  bool get hasChildren => children.isNotEmpty;
}

/// A node paired with its depth, for flat list rendering.
class OutlineRow {
  final OutlineNode node;
  final int depth;

  const OutlineRow(this.node, this.depth);
}

/// Builds and navigates a hierarchical document outline (a.k.a. mind-map /
/// table of contents) from a flat list of headings.
///
/// The heading list comes from either the PDF's native bookmarks or the
/// backend `/document-ai/outline` AI heading extraction — both hand back
/// `{title, page, level}`. This service turns that flat, level-tagged list into
/// a real tree (nesting deeper levels under the most recent shallower heading),
/// and provides the operations a panel needs:
///
/// - [build] : flat headings → tree
/// - [flattenVisible] : tree → rows honouring collapse state (for a ListView)
/// - [expandAll] / [collapseAll] / [toggle]
/// - [nearestForPage] : which outline entry corresponds to the current page
///
/// Pure Dart, no Flutter dependency → fully unit-testable.
class DocumentOutlineService {
  const DocumentOutlineService();

  /// Turn a flat, level-tagged heading list into a nested tree.
  ///
  /// A heading becomes a child of the most recent previous heading with a
  /// strictly smaller level. Headings that appear before any shallower heading
  /// (or the very first) become roots. Non-positive levels are treated as 1.
  List<OutlineNode> build(List<OutlineHeading> headings) {
    final roots = <OutlineNode>[];
    final stack = <OutlineNode>[];

    for (final h in headings) {
      final level = h.level < 1 ? 1 : h.level;
      final node = OutlineNode(title: h.title, page: h.page, level: level);

      // Pop until the stack top is a strictly shallower heading.
      while (stack.isNotEmpty && stack.last.level >= level) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        roots.add(node);
      } else {
        stack.last.children.add(node);
      }
      stack.add(node);
    }
    return roots;
  }

  /// Depth-first flatten to rows, skipping the subtree of collapsed nodes.
  List<OutlineRow> flattenVisible(List<OutlineNode> roots) {
    final rows = <OutlineRow>[];
    void visit(OutlineNode n, int depth) {
      rows.add(OutlineRow(n, depth));
      if (n.expanded) {
        for (final c in n.children) {
          visit(c, depth + 1);
        }
      }
    }

    for (final r in roots) {
      visit(r, 0);
    }
    return rows;
  }

  /// Full depth-first flatten ignoring collapse state (e.g. for search).
  List<OutlineNode> flattenAll(List<OutlineNode> roots) {
    final out = <OutlineNode>[];
    void visit(OutlineNode n) {
      out.add(n);
      for (final c in n.children) {
        visit(c);
      }
    }

    for (final r in roots) {
      visit(r);
    }
    return out;
  }

  void expandAll(List<OutlineNode> roots) =>
      _setExpandedRecursive(roots, true);

  void collapseAll(List<OutlineNode> roots) =>
      _setExpandedRecursive(roots, false);

  /// Toggle a node's expanded state; returns the new state.
  bool toggle(OutlineNode node) => node.expanded = !node.expanded;

  /// The deepest outline node whose page is <= [page] in document order — i.e.
  /// the section the given page belongs to. Returns null if none precedes it.
  OutlineNode? nearestForPage(List<OutlineNode> roots, int page) {
    OutlineNode? best;
    for (final n in flattenAll(roots)) {
      if (n.page <= page) {
        if (best == null || n.page >= best.page) best = n;
      }
    }
    return best;
  }

  void _setExpandedRecursive(List<OutlineNode> nodes, bool value) {
    for (final n in nodes) {
      n.expanded = value;
      _setExpandedRecursive(n.children, value);
    }
  }
}
