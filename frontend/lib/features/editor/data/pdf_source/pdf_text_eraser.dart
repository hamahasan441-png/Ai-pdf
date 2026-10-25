import 'dart:convert' show latin1;
import 'dart:typed_data';

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';
import 'package:ai_pdf/features/editor/data/pdf_source/pdf_standard_widths.dart';

/// A rectangle in a page's default user space: [x0, y0, x1, y1], x0 < x1,
/// y0 < y1.
typedef UserRect = List<double>;

/// Result of [PdfTextEraser.erase].
class TextEraseResult {
  /// The rewritten content stream (decoded, unfiltered).
  final Uint8List content;

  /// Glyphs removed from the regions.
  final int removed;

  /// Glyphs inside the regions that could not be removed: text in a Form
  /// XObject, a font without widths, a vertical or non-Identity CID font, a
  /// Type 3 font. When this is not zero the content must not be used: the
  /// region would still hold the original text.
  final int unresolved;

  const TextEraseResult(this.content, this.removed, this.unresolved);

  bool get complete => unresolved == 0;
}

/// Removes the glyphs whose centre lies inside given regions from a page's
/// content stream, so edited text is really gone from the file (not just
/// covered) and the page keeps its vector content.
///
/// Everything except the affected text-showing operators is copied byte for
/// byte. A removed glyph becomes a TJ position adjustment of exactly its
/// advance, so the glyphs after it, in the same operator or later ones in
/// the same text object, stay where they were.
class PdfTextEraser {
  PdfTextEraser(this.store);

  final PdfObjectStore store;

  TextEraseResult erase(Uint8List content, PdfValue? resources, List<UserRect> regions) {
    if (regions.isEmpty) return TextEraseResult(content, 0, 0);
    final fonts = _Fonts(store, resources);
    final first = _Run(content, fonts, regions, store, resources, rewrite: true).go();
    // Re-scan the result: any glyph still inside a region is a failure.
    final check = _Run(first.content, fonts, regions, store, resources, rewrite: false).go();
    final left = check.removed + check.unresolved;
    return TextEraseResult(first.content, first.removed, left > first.unresolved ? left : first.unresolved);
  }
}

class _FontInfo {
  final bool twoByte;
  final Map<int, double> widths; // glyph space units (1/1000 em)
  final double defaultWidth;

  /// Widths are known exactly (from /Widths or /W), so removed glyphs can be
  /// replaced by their exact advance.
  final bool exact;

  const _FontInfo({required this.twoByte, required this.widths, required this.defaultWidth, required this.exact});

  static const unknown = _FontInfo(twoByte: false, widths: {}, defaultWidth: 500, exact: false);

  double width(int code) => widths[code] ?? defaultWidth;
}

class _Fonts {
  _Fonts(this.s, PdfValue? resources) {
    final res = s.resolve(resources);
    final fonts = res is PdfDict ? s.resolve(res['/Font']) : null;
    if (fonts is PdfDict) dict = fonts;
  }

  final PdfObjectStore s;
  PdfDict? dict;
  final Map<String, _FontInfo> _cache = {};

  _FontInfo operator [](String name) => _cache.putIfAbsent(name, () => _load(name));

  double _num(PdfValue? v, double d) {
    final r = s.resolve(v);
    return r is PdfNum ? r.toDouble() : d;
  }

  _FontInfo _load(String name) {
    final f = s.resolve(dict?[name]);
    if (f is! PdfDict) return _FontInfo.unknown;
    final subtype = (s.resolve(f['/Subtype']) as PdfName?)?.name;
    if (subtype == '/Type0') {
      final enc = s.resolve(f['/Encoding']);
      if (enc is! PdfName || enc.name != '/Identity-H') return _FontInfo.unknown;
      final desc = s.resolve(f['/DescendantFonts']);
      final cid = desc is PdfArray && desc.items.isNotEmpty ? s.resolve(desc.items.first) : null;
      if (cid is! PdfDict) return _FontInfo.unknown;
      final widths = <int, double>{};
      final w = s.resolve(cid['/W']);
      if (w is PdfArray) {
        final items = [for (final i in w.items) s.resolve(i)];
        var i = 0;
        while (i < items.length) {
          final a = items[i];
          if (a is! PdfNum || i + 1 >= items.length) break;
          final b = items[i + 1];
          if (b is PdfArray) {
            var c = a.toInt();
            for (final x in b.items) {
              widths[c++] = _num(x, 0);
            }
            i += 2;
          } else if (b is PdfNum && i + 2 < items.length) {
            final wv = _num(items[i + 2], 0);
            for (var c = a.toInt(); c <= b.toInt() && c - a.toInt() < 65536; c++) {
              widths[c] = wv;
            }
            i += 3;
          } else {
            break;
          }
        }
      }
      return _FontInfo(twoByte: true, widths: widths, defaultWidth: _num(cid['/DW'], 1000), exact: true);
    }
    if (subtype == '/Type3') return _FontInfo.unknown; // widths are in a custom glyph space
    final base = _baseName(f);
    final standard = base == null ? null : standard14Widths(base);
    // A standard 14 font may omit /Widths. Its metrics are the AFM widths,
    // the same table the text extractor uses for the word box.
    if (standard != null && subtype == '/Type1') {
      return _FontInfo(
        twoByte: false,
        widths: {for (var i = 0; i < standard.length; i++) i: standard[i].toDouble()},
        defaultWidth: standard[0].toDouble(),
        exact: true,
      );
    }
    final first = _num(f['/FirstChar'], 0).toInt();
    final ws = s.resolve(f['/Widths']);
    if (ws is! PdfArray) return _FontInfo.unknown; // a custom font with no metrics
    final desc = s.resolve(f['/FontDescriptor']);
    final missing = desc is PdfDict ? _num(desc['/MissingWidth'], 0) : 0.0;
    return _FontInfo(
      twoByte: false,
      widths: {for (var i = 0; i < ws.items.length; i++) first + i: _num(ws.items[i], missing)},
      defaultWidth: missing,
      exact: true,
    );
  }

  /// Base font name without a subset prefix. A subset (`ABC+Helvetica`) does
  /// not use the standard widths: its encoding is its own.
  String? _baseName(PdfDict f) {
    final n = s.resolve(f['/BaseFont']);
    if (n is! PdfName) return null;
    var name = n.name.startsWith('/') ? n.name.substring(1) : n.name;
    if (name.contains('+')) return null;
    return name;
  }
}

class _Mat {
  double a, b, c, d, e, f;
  _Mat(this.a, this.b, this.c, this.d, this.e, this.f);
  _Mat.identity() : this(1, 0, 0, 1, 0, 0);
  _Mat copy() => _Mat(a, b, c, d, e, f);

  /// this × m: m applied first, then this (PDF `cm` order: new × current).
  _Mat times(_Mat m) => _Mat(
        m.a * a + m.b * c,
        m.a * b + m.b * d,
        m.c * a + m.d * c,
        m.c * b + m.d * d,
        m.e * a + m.f * c + e,
        m.e * b + m.f * d + f,
      );

  (double, double) apply(double x, double y) => (a * x + c * y + e, b * x + d * y + f);
}

/// A token of a content stream with its byte span.
class _Tok {
  final int start, end;
  final PdfValue? value;
  final String? op;
  const _Tok(this.start, this.end, {this.value, this.op});
}

class _Out {
  final Uint8List content;
  final int removed, unresolved;
  const _Out(this.content, this.removed, this.unresolved);
}

class _Run {
  _Run(this.data, this.fonts, this.regions, this.store, this.resources,
      {required this.rewrite, _Mat? initialCtm, this.depth = 0})
      : ctm = initialCtm ?? _Mat.identity();

  final Uint8List data;
  final _Fonts fonts;
  final List<UserRect> regions;
  final PdfObjectStore store;
  final PdfValue? resources;
  final bool rewrite;
  final int depth;

  final out = BytesBuilder(copy: false);
  var copied = 0;
  var removed = 0;
  var unresolved = 0;

  _Mat ctm;
  final ctmStack = <_Mat>[];
  var tm = _Mat.identity();
  var lm = _Mat.identity();
  var font = _FontInfo.unknown;
  var fontSize = 0.0;
  var charSpace = 0.0, wordSpace = 0.0, hScale = 1.0, leading = 0.0;

  bool inside(double x, double y) {
    for (final r in regions) {
      if (x >= r[0] && x <= r[2] && y >= r[1] && y <= r[3]) return true;
    }
    return false;
  }

  bool boxTouches(double x0, double y0, double x1, double y1) {
    for (final r in regions) {
      if (x1 >= r[0] && x0 <= r[2] && y1 >= r[1] && y0 <= r[3]) return true;
    }
    return false;
  }

  void translateLine(double tx, double ty) {
    lm = lm.times(_Mat(1, 0, 0, 1, tx, ty));
    tm = lm.copy();
  }

  void advance(double tx) => tm = tm.times(_Mat(1, 0, 0, 1, tx, 0));

  List<int> codesOf(PdfString s) {
    final b = s.bytes;
    if (!font.twoByte) return b;
    return [for (var i = 0; i + 1 < b.length; i += 2) b[i] << 8 | b[i + 1]];
  }

  /// Glyph displacement in text space for [code].
  double glyphAdvance(int code) {
    var tx = font.width(code) / 1000 * fontSize + charSpace;
    if (!font.twoByte && code == 32) tx += wordSpace;
    return tx * hScale;
  }

  /// Whether the glyph at the current text position falls in a region.
  bool glyphInside(int code) {
    final w = font.width(code) / 1000 * fontSize * hScale;
    final m = ctm.times(tm);
    final (x, y) = m.apply(w / 2, fontSize * 0.3);
    return inside(x, y);
  }

  /// Walks the elements of a show operator ([strings] and TJ numbers).
  /// Returns the rewritten TJ array, or null when nothing was removed.
  String? show(List<PdfValue> items) {
    final parts = <String>[];
    final kept = BytesBuilder();
    var pendingAdjust = 0.0;
    var hit = false;

    void flushKept() {
      if (kept.isEmpty) return;
      final bytes = kept.takeBytes();
      parts.add('<${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}>');
    }

    void flushAdjust() {
      if (pendingAdjust == 0) return;
      parts.add(PdfNum.of(pendingAdjust).raw);
      pendingAdjust = 0;
    }

    for (final item in items) {
      if (item is PdfNum) {
        flushKept();
        pendingAdjust += item.toDouble();
        advance(-item.toDouble() / 1000 * fontSize * hScale);
        continue;
      }
      if (item is! PdfString) continue;
      for (final code in codesOf(item)) {
        final inRegion = glyphInside(code);
        final adv = glyphAdvance(code);
        if (inRegion && fontSize != 0 && font.exact) {
          hit = true;
          removed++;
          flushKept();
          // A TJ number n moves by -n/1000 × size × Tz.
          pendingAdjust += -adv * 1000 / (fontSize * hScale);
        } else {
          if (inRegion) unresolved++;
          flushAdjust();
          if (font.twoByte) {
            kept.add([code >> 8, code & 0xFF]);
          } else {
            kept.addByte(code);
          }
        }
        advance(adv);
      }
    }
    if (!hit) return null;
    flushKept();
    flushAdjust();
    return '[${parts.join(' ')}] TJ';
  }

  void replace(int start, int end, String text) {
    if (!rewrite) return;
    out.add(Uint8List.sublistView(data, copied, start));
    out.add(latin1.encode(text));
    copied = end;
  }

  double n(PdfValue? v, [double d = 0]) => v is PdfNum ? v.toDouble() : d;

  _Out go() {
    final lx = PdfLexer(data, 0);
    final operands = <_Tok>[];
    while (true) {
      final tok = _next(lx);
      if (tok == null) break;
      if (tok.op == null) {
        operands.add(tok);
        continue;
      }
      final args = [for (final t in operands) t.value];
      final from = operands.isEmpty ? tok.start : operands.first.start;
      operands.clear();
      switch (tok.op!) {
        case 'q':
          ctmStack.add(ctm.copy());
        case 'Q':
          if (ctmStack.isNotEmpty) ctm = ctmStack.removeLast();
        case 'cm' when args.length >= 6:
          ctm = ctm.times(_Mat(n(args[0], 1), n(args[1]), n(args[2]), n(args[3], 1), n(args[4]), n(args[5])));
        case 'BT':
          tm = _Mat.identity();
          lm = _Mat.identity();
        case 'Tm' when args.length >= 6:
          tm = _Mat(n(args[0], 1), n(args[1]), n(args[2]), n(args[3], 1), n(args[4]), n(args[5]));
          lm = tm.copy();
        case 'Td' when args.length >= 2:
          translateLine(n(args[0]), n(args[1]));
        case 'TD' when args.length >= 2:
          leading = -n(args[1]);
          translateLine(n(args[0]), n(args[1]));
        case 'T*':
          translateLine(0, -leading);
        case 'TL' when args.isNotEmpty:
          leading = n(args.last);
        case 'Tc' when args.isNotEmpty:
          charSpace = n(args.last);
        case 'Tw' when args.isNotEmpty:
          wordSpace = n(args.last);
        case 'Tz' when args.isNotEmpty:
          hScale = n(args.last, 100) / 100;
        case 'Tf' when args.length >= 2:
          final name = args[args.length - 2];
          fontSize = n(args.last);
          font = name is PdfName ? fonts[name.name] : _FontInfo.unknown;
        case 'Tj' when args.isNotEmpty && args.last is PdfString:
          final r = show([args.last!]);
          if (r != null) replace(from, tok.end, r);
        case "'" when args.isNotEmpty && args.last is PdfString:
          translateLine(0, -leading);
          final r = show([args.last!]);
          if (r != null) replace(from, tok.end, 'T* $r');
        case '"' when args.length >= 3 && args.last is PdfString:
          wordSpace = n(args[args.length - 3]);
          charSpace = n(args[args.length - 2]);
          translateLine(0, -leading);
          final r = show([args.last!]);
          if (r != null) {
            replace(from, tok.end, '${PdfNum.of(wordSpace).raw} Tw ${PdfNum.of(charSpace).raw} Tc T* $r');
          }
        case 'TJ' when args.isNotEmpty && args.last is PdfArray:
          final r = show((args.last as PdfArray).items);
          if (r != null) replace(from, tok.end, r);
        case 'Do' when args.isNotEmpty && args.last is PdfName:
          _form((args.last as PdfName).name);
        default:
          break;
      }
    }
    if (!rewrite) return _Out(data, removed, unresolved);
    out.add(Uint8List.sublistView(data, copied));
    return _Out(out.toBytes(), removed, unresolved);
  }

  /// Text inside a Form XObject cannot be erased here (the form may be shared
  /// by other pages). Glyphs of a form that fall in a region count as
  /// unresolved, so the caller falls back to flattening the page.
  void _form(String name) {
    final res = store.resolve(resources);
    final xo = res is PdfDict ? store.resolve(res['/XObject']) : null;
    final ref = xo is PdfDict ? xo[name] : null;
    if (ref is! PdfRef) return;
    final obj = store.object(ref.num);
    final dict = obj?.value;
    if (obj?.stream == null || dict is! PdfDict || dict['/Subtype'] != const PdfName('/Form')) return;
    final bbox = store.resolve(dict['/BBox']);
    if (bbox is! PdfArray || bbox.items.length != 4) return;
    final b = [for (final v in bbox.items) n(store.resolve(v))];
    final mv = store.resolve(dict['/Matrix']);
    var m = ctm;
    if (mv is PdfArray && mv.items.length == 6) {
      final x = [for (final v in mv.items) n(store.resolve(v))];
      m = ctm.times(_Mat(x[0], x[1], x[2], x[3], x[4], x[5]));
    }
    final pts = [m.apply(b[0], b[1]), m.apply(b[2], b[1]), m.apply(b[0], b[3]), m.apply(b[2], b[3])];
    final xs = pts.map((p) => p.$1), ys = pts.map((p) => p.$2);
    if (!boxTouches(xs.reduce((a, b) => a < b ? a : b), ys.reduce((a, b) => a < b ? a : b),
        xs.reduce((a, b) => a > b ? a : b), ys.reduce((a, b) => a > b ? a : b))) {
      return;
    }
    Uint8List body;
    try {
      body = store.decodeStream(obj!);
    } on PdfSourceException {
      unresolved++;
      return;
    }
    if (depth >= 8) {
      unresolved++;
      return;
    }
    final formRes = dict['/Resources'] ?? resources;
    final scan = _Run(body, _Fonts(store, formRes), regions, store, formRes,
            rewrite: false, initialCtm: m, depth: depth + 1)
        .go();
    unresolved += scan.removed + scan.unresolved;
  }

  /// Next token, or null at the end. Inline images are skipped whole.
  _Tok? _next(PdfLexer lx) {
    lx.skipWhitespace();
    if (lx.pos >= data.length) return null;
    final start = lx.pos;
    final c = data[lx.pos];
    final isOperand = c == 0x2F || c == 0x28 || c == 0x3C || c == 0x5B ||
        c == 0x2B || c == 0x2D || c == 0x2E || (c >= 0x30 && c <= 0x39);
    if (isOperand) {
      final v = lx.readValue();
      return _Tok(start, lx.pos, value: v);
    }
    if (PdfLexer.isDelim(c)) {
      lx.pos++; // stray delimiter (] or }): skip
      return _Tok(start, lx.pos, op: '');
    }
    final word = lx.readKeyword();
    if (word == 'true' || word == 'false' || word == 'null') {
      return _Tok(start, lx.pos, value: word == 'null' ? const PdfNull() : PdfBool(word == 'true'));
    }
    if (word == 'BI') {
      // Inline image: skip to the "EI" that follows the data.
      final id = _find(data, 'ID', lx.pos);
      var p = id < 0 ? data.length : id + 3;
      while (p < data.length - 1) {
        if (data[p] == 0x45 && data[p + 1] == 0x49 &&
            (p == 0 || PdfLexer.isWhite(data[p - 1])) &&
            (p + 2 >= data.length || PdfLexer.isWhite(data[p + 2]))) {
          break;
        }
        p++;
      }
      lx.pos = (p + 2).clamp(0, data.length);
      return _Tok(start, lx.pos, op: 'BI');
    }
    return _Tok(start, lx.pos, op: word);
  }

  static int _find(Uint8List d, String s, int from) {
    final a = s.codeUnitAt(0), b = s.codeUnitAt(1);
    for (var i = from; i < d.length - 1; i++) {
      if (d[i] == a && d[i + 1] == b) return i;
    }
    return -1;
  }
}

/// [norm] (0..1 from the displayed top left, as the editor stores marks)
/// in the page's user space, for a page with [crop] shown at [rotate].
UserRect userRectOf(List<double> norm, List<double> crop, int rotate) {
  final w = crop[2] - crop[0];
  final h = crop[3] - crop[1];
  final r = ((rotate % 360) + 360) % 360;
  // Inverse of displayRect: displayed (X, Y) → unrotated (u, v).
  (double, double) back(double x, double y) {
    final (u, v) = switch (r) {
      90 => (y, x),
      180 => (1 - x, y),
      270 => (1 - y, 1 - x),
      _ => (x, 1 - y),
    };
    return (crop[0] + u * w, crop[1] + v * h);
  }

  final a = back(norm[0], norm[1]);
  final b = back(norm[2], norm[3]);
  return [
    a.$1 < b.$1 ? a.$1 : b.$1,
    a.$2 < b.$2 ? a.$2 : b.$2,
    a.$1 < b.$1 ? b.$1 : a.$1,
    a.$2 < b.$2 ? b.$2 : a.$2,
  ];
}


/// Erases the glyphs inside [displayRegions] (0..1 from the displayed top
/// left, after [quarterTurns] extra turns) from [page]'s content. A content
/// stream that cannot be decoded gives an incomplete result.
TextEraseResult erasePageText(
  PdfObjectStore s,
  PdfPageInfo page,
  List<List<double>> displayRegions, {
  int quarterTurns = 0,
}) {
  final rotate = (page.rotate + 90 * quarterTurns) % 360;
  final regions = [for (final r in displayRegions) userRectOf(r, page.cropBox, rotate)];
  final contents = s.resolve(page.attr('/Contents'));
  final parts = contents is PdfArray ? contents.items : [page.attr('/Contents')];
  final b = BytesBuilder(copy: false);
  try {
    for (final p in parts) {
      if (p is! PdfRef) continue;
      final obj = s.object(p.num);
      if (obj == null || obj.stream == null) continue;
      b.add(s.decodeStream(obj));
      b.addByte(0x0A); // streams of one page join at token boundaries
    }
  } on PdfSourceException {
    return TextEraseResult(Uint8List(0), 0, 1);
  }
  return PdfTextEraser(s).erase(b.toBytes(), page.attr('/Resources'), regions);
}
