import 'dart:ui' show Rect;

import 'package:ai_pdf/features/editor/data/document_search_service.dart';
import 'package:ai_pdf/features/editor/data/editor_existing_text_service.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// The marks a replace adds, by page, and how many matches they replace.
class TextReplacePlan {
  final Map<int, List<EditorAnnotation>> items;
  final int replaced;

  const TextReplacePlan(this.items, this.replaced);
}

/// Find & replace over the PDF's own text.
///
/// Each matched word becomes the same edit as selecting it and typing: a
/// whiteout marked [eraseTextKey] (the export removes those glyphs from the
/// page content) and a text box with the new word in the matched style. An
/// empty replacement leaves only the whiteout, which deletes the text.
class TextReplaceService {
  const TextReplaceService();

  static const _existing = EditorExistingTextService();

  /// The marks to add, by page, to replace [matches] with [replacement].
  ///
  /// [pages] must be the text layer the matches were found in. Several matches
  /// in one word become one edit. A match whose text no longer reads the same
  /// in [pages] (the layer changed since the search) is skipped.
  TextReplacePlan plan(
    Map<int, List<PdfTextElement>> pages,
    Iterable<SearchMatch> matches,
    String replacement, {
    Map<int, double> pageHeightPt = const {},
  }) {
    final byWord = <(int, int), List<SearchMatch>>{};
    for (final m in matches) {
      byWord.putIfAbsent((m.pageIndex, m.elementIndex), () => []).add(m);
    }
    final out = <int, List<EditorAnnotation>>{};
    var total = 0;
    final keys = byWord.keys.toList()
      ..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    for (final key in keys) {
      final (page, index) = key;
      final words = pages[page];
      if (words == null || index < 0 || index >= words.length) continue;
      final word = words[index];
      final hits = byWord[key]!..sort((a, b) => a.start.compareTo(b.start));
      final text = StringBuffer();
      var at = 0;
      var replaced = 0;
      for (final m in hits) {
        if (m.start < at || m.end > word.text.length || word.text.substring(m.start, m.end) != m.text) {
          continue;
        }
        text
          ..write(word.text.substring(at, m.start))
          ..write(replacement);
        at = m.end;
        replaced++;
      }
      if (replaced == 0) continue;
      total += replaced;
      text.write(word.text.substring(at));
      final draft = _existing.draftForWords([word], pageHeightPt: pageHeightPt[page] ?? 0);
      final items = out.putIfAbsent(page, () => []);
      items.add(draft.whiteout);
      final next = text.toString();
      if (next.trim().isNotEmpty) {
        draft.textBox.text = next;
        items.add(draft.textBox);
      }
    }
    return TextReplacePlan(out, total);
  }

  /// [pages] without the words an edit already removes: those under a
  /// visible whiteout marked [eraseTextKey]. Searching this layer does not
  /// find text that is already replaced; undoing the edit brings it back.
  Map<int, List<PdfTextElement>> unreplaced(
    Map<int, List<PdfTextElement>> pages,
    Map<int, PageLayer> layers,
  ) {
    final out = <int, List<PdfTextElement>>{};
    for (final entry in pages.entries) {
      final erased = <Rect>[
        for (final s in layers[entry.key]?.shapes ?? const <ShapeAnnotation>[])
          if (s.visible && s.type == ShapeType.whiteout && s.metadata[eraseTextKey] == true)
            Rect.fromPoints(s.start, s.end),
      ];
      out[entry.key] = erased.isEmpty
          ? entry.value
          : [
              for (final w in entry.value)
                if (!erased.any((r) => r.contains(w.rect.center))) w,
            ];
    }
    return out;
  }
}
