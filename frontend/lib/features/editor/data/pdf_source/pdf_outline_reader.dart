import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/domain/services/document_outline_service.dart';

/// Reads the document outline (bookmarks) from a PDF.
///
/// Follows /Outlines → /First → /Next, with /Dest or a /GoTo action, and
/// resolves named destinations through the catalog's /Dests dictionary and
/// the /Names /Dests name tree. Bookmarks whose target is not a page of this
/// file (another file, a URI, a broken reference) are left out. Cycles and
/// absurd depths stop the walk instead of hanging.
class PdfOutlineReader {
  const PdfOutlineReader();

  static const int maxEntries = 5000;
  static const int maxDepth = 32;

  /// Headings in document order. Page numbers are 0-based. Empty when the
  /// file has no outline.
  List<OutlineHeading> read(PdfObjectStore store) {
    final catalog = store.catalog;
    final outlines = store.resolve(catalog['/Outlines']);
    if (outlines is! PdfDict) return const [];
    final pageIndex = <PdfRef, int>{
      for (var i = 0; i < store.pages.length; i++) store.pages[i].ref: i,
    };
    final named = _NamedDests(store, catalog);
    final out = <OutlineHeading>[];
    final seen = <int>{};

    void walk(PdfValue? first, int depth) {
      var ref = first;
      while (ref is PdfRef && out.length < maxEntries) {
        if (!seen.add(ref.num)) return;
        final item = store.resolve(ref);
        if (item is! PdfDict) return;
        final title = _text(store.resolve(item['/Title']));
        final page = _pageOf(store, item, pageIndex, named);
        if (title != null && title.trim().isNotEmpty && page != null) {
          out.add(OutlineHeading(title: title.trim(), page: page, level: depth + 1));
        }
        if (depth + 1 < maxDepth) walk(item['/First'], depth + 1);
        ref = item['/Next'];
      }
    }

    walk(outlines['/First'], 0);
    return out;
  }

  int? _pageOf(PdfObjectStore s, PdfDict item, Map<PdfRef, int> pages, _NamedDests named) {
    var dest = s.resolve(item['/Dest']);
    if (dest == null) {
      final action = s.resolve(item['/A']);
      if (action is PdfDict && (s.resolve(action['/S']) as PdfName?)?.name == '/GoTo') {
        dest = s.resolve(action['/D']);
      }
    }
    if (dest is PdfName) dest = named.lookup(dest.name.substring(1));
    if (dest is PdfString) dest = named.lookup(_text(dest) ?? '');
    // A named destination may be a dictionary holding the array in /D.
    if (dest is PdfDict) dest = s.resolve(dest['/D']);
    if (dest is! PdfArray || dest.items.isEmpty) return null;
    final target = dest.items.first;
    if (target is PdfRef) return pages[target];
    return null; // a page number here means a remote (other-file) target
  }
}

/// Decodes a PDF text string: UTF-16BE with BOM, UTF-8 with BOM, otherwise
/// PDFDocEncoding (Latin-1 is used for it; they differ only in rarely used
/// punctuation).
String? _text(PdfValue? v) {
  if (v is! PdfString) return null;
  final b = v.bytes;
  if (b.length >= 2 && b[0] == 0xFE && b[1] == 0xFF) {
    final units = <int>[for (var i = 2; i + 1 < b.length; i += 2) (b[i] << 8) | b[i + 1]];
    return String.fromCharCodes(units);
  }
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    return utf8.decode(Uint8List.sublistView(b, 3), allowMalformed: true);
  }
  return latin1.decode(b);
}

/// Named destinations from /Dests (PDF 1.1) and the /Names /Dests tree.
class _NamedDests {
  final PdfObjectStore s;
  final PdfDict catalog;
  Map<String, PdfValue>? _all;

  _NamedDests(this.s, this.catalog);

  PdfValue? lookup(String name) => s.resolve((_all ??= _load())[name]);

  Map<String, PdfValue> _load() {
    final out = <String, PdfValue>{};
    final old = s.resolve(catalog['/Dests']);
    if (old is PdfDict) {
      old.entries.forEach((k, v) => out[k.substring(1)] = v);
    }
    final names = s.resolve(catalog['/Names']);
    if (names is PdfDict) {
      final seen = <PdfValue>{};
      void tree(PdfValue? node, int depth) {
        if (depth > PdfOutlineReader.maxDepth || out.length > 100000) return;
        if (node is PdfRef && !seen.add(node)) return;
        final n = s.resolve(node);
        if (n is! PdfDict) return;
        final pairs = s.resolve(n['/Names']);
        if (pairs is PdfArray) {
          for (var i = 0; i + 1 < pairs.items.length; i += 2) {
            final key = s.resolve(pairs.items[i]);
            if (key is PdfString) out[_text(key) ?? ''] = pairs.items[i + 1];
          }
        }
        final kids = s.resolve(n['/Kids']);
        if (kids is PdfArray) {
          for (final k in kids.items) {
            tree(k, depth + 1);
          }
        }
      }

      tree(names['/Dests'], 0);
    }
    return out;
  }
}
