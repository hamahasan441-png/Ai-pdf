import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Marks a text box as the document's page number, so a later pass can
/// rewrite it instead of stacking another badge on top.
const String pageNumberBadgeKey = 'pageNumberBadge';

bool isPageNumberBadge(EditorAnnotation annotation) =>
    annotation.metadata[pageNumberBadgeKey] == true;

/// The label FlexiPDF and PDF24 both print: the shown page, then the total.
String pageNumberLabel(int index, int pageCount) => '${index + 1} / $pageCount';

/// A real text box at the bottom centre of the displayed page. It stays
/// searchable. It is not burned into a flattened page image.
TextAnnotation pageNumberBadge(int index, int pageCount) {
  final box = TextAnnotation(
    const Offset(0.12, 0.955),
    pageNumberLabel(index, pageCount),
    const Color(0xFF1B2130),
    0.015,
    false,
    textAlign: TextAlign.center,
    width: 0.76,
  );
  box.metadata[pageNumberBadgeKey] = true;
  return box;
}

bool documentHasPageNumbers(Map<int, PageLayer> layers) {
  for (final layer in layers.values) {
    if (layer.items.any(isPageNumberBadge)) return true;
  }
  return false;
}

/// Writes one badge on every page and drops any previous badges, including
/// ones left on a page index that no longer exists.
int syncPageNumbers(Map<int, PageLayer> layers, int pageCount) {
  if (pageCount < 1) return 0;
  for (final layer in layers.values) {
    layer.items.removeWhere(isPageNumberBadge);
  }
  for (var i = 0; i < pageCount; i++) {
    layers.putIfAbsent(i, PageLayer.new).items.add(pageNumberBadge(i, pageCount));
  }
  return pageCount;
}

/// After a page is moved, inserted or deleted, the badges that are already
/// there are rewritten. A document that was never numbered is left alone.
int refreshPageNumbers(Map<int, PageLayer> layers, int pageCount) {
  if (!documentHasPageNumbers(layers)) return 0;
  return syncPageNumbers(layers, pageCount);
}
