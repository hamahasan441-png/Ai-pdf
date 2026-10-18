import 'dart:io' show File, ZLibDecoder;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Rect;

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// Reads positioned text out of a PDF's content streams.
///
/// This is the on-device stand-in for the text layer that pdf.js
/// (`getTextContent`) and Apache PDFBox build from the same PDF 32000 text
/// operators (`BT`/`ET`, `Tm`, `Td`, `Tf`, `Tj`, `TJ`). It does not copy those
/// projects; it implements the spec subset the editor needs so highlight,
/// underline, strikeout, squiggly and Find snap to real glyphs — including
/// Kurdish/Arabic when the font has a ToUnicode map. Scanned pages with no
/// text operators return nothing and the editor falls back to on-device OCR.
///
/// Failures never throw: a PDF this parser does not understand yields an
/// empty map and the rest of the editor keeps working.
class PdfContentTextExtractor {
  const PdfContentTextExtractor();


  Map<int, List<PdfTextElement>> extract(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > 80 * 1024 * 1024) return const {};
    try {
      final doc = _PdfDoc(bytes);
      doc.parse();
      return doc.pages;
    } catch (_) {
      return const {};
    }
  }
}

/// Isolate entry point. [compute] can only call a top-level function.
/// Reads the file inside the isolate so a large PDF does not freeze the page.
Map<int, List<PdfTextElement>> extractPdfTextLayerFromPath(String path) {
  try {
    final bytes = File(path).readAsBytesSync();
    return const PdfContentTextExtractor().extract(bytes);
  } catch (_) {
    return const {};
  }
}

class _M {
  double a, b, c, d, e, f;
  _M(this.a, this.b, this.c, this.d, this.e, this.f);
  _M.identity() : this(1, 0, 0, 1, 0, 0);
  _M copy() => _M(a, b, c, d, e, f);
}

/// a ∘ b: the matrix that applies [b] first, then [a].
_M _mul(_M a, _M b) => _M(
      a.a * b.a + a.c * b.b,
      a.b * b.a + a.d * b.b,
      a.a * b.c + a.c * b.d,
      a.b * b.c + a.d * b.d,
      a.a * b.e + a.c * b.f + a.e,
      a.b * b.e + a.d * b.f + a.f,
    );

class _V {
  final double? number;
  final String? name;
  final String? str;
  final int? ref;
  final List<_V>? array;
  final Map<String, _V>? dict;
  const _V.number(this.number)
      : name = null,
        str = null,
        ref = null,
        array = null,
        dict = null;
  const _V.name(this.name)
      : number = null,
        str = null,
        ref = null,
        array = null,
        dict = null;
  const _V.str(this.str)
      : number = null,
        name = null,
        ref = null,
        array = null,
        dict = null;
  const _V.ref(this.ref)
      : number = null,
        name = null,
        str = null,
        array = null,
        dict = null;
  const _V.array(this.array)
      : number = null,
        name = null,
        str = null,
        ref = null,
        dict = null;
  const _V.dict(this.dict)
      : number = null,
        name = null,
        str = null,
        ref = null,
        array = null;
}

class _Obj {
  final _V value;
  final Uint8List? stream;
  _Obj(this.value, this.stream);
  Map<String, _V> get dict => value.dict ?? const {};
}

class _Font {
  final Map<int, String> unicode = {};
  List<double>? widths;
  int firstChar = 0;
  bool twoByte = false;
  String baseName = '';

  double widthOf(int code) {
    final w = widths;
    if (w != null) {
      final i = code - firstChar;
      if (i >= 0 && i < w.length) return w[i] / 1000.0;
    }
    return 0.5;
  }
}

class _PdfDoc {
  final Uint8List bytes;
  late final String s;
  final Map<int, int> xref = {};
  final Map<int, (int, int)> compressed = {};
  final Map<int, _Obj> cache = {};
  final Set<int> _xrefSeen = {};
  int? root;
  final Map<int, List<PdfTextElement>> pages = {};

  _PdfDoc(this.bytes) : s = String.fromCharCodes(bytes);

  void parse() {
    final start = _startXref();
    if (start != null) _readXref(start);
    if (xref.isEmpty) _scanObjects();
    if (root == null) return;
    final catalog = _load(root!);
    final pagesRef = catalog.dict['/Pages']?.ref;
    if (pagesRef == null) return;
    final found = <_PageInfo>[];
    _walkPages(pagesRef, null, null, found, 0, null, 0);
    for (var i = 0; i < found.length; i++) {
      final elements = _extractPage(found[i]);
      if (elements.isNotEmpty) pages[i] = elements;
    }
  }

  int? _startXref() {
    final from = math.max(0, s.length - 65536);
    final i = s.lastIndexOf('startxref', s.length);
    if (i < from && i < 0) return null;
    if (i < 0) return null;
    final m = RegExp(r'startxref\s+(\d+)').firstMatch(s.substring(i));
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  void _readXref(int offset) {
    if (offset < 0 || offset >= s.length || !_xrefSeen.add(offset)) return;
    _skipWsAt(offset);
    if (s.startsWith('xref', offset)) {
      _readClassic(offset);
    } else {
      _readXrefStream(offset);
    }
  }

  void _readClassic(int offset) {
    var i = offset + 4;
    int? prev;
    while (i < s.length) {
      while (i < s.length && _ws(s.codeUnitAt(i))) {
        i++;
      }
      if (s.startsWith('trailer', i)) break;
      final head = RegExp(r'(\d+)\s+(\d+)').matchAsPrefix(s, i);
      if (head == null) break;
      final startNum = int.parse(head.group(1)!);
      final count = int.parse(head.group(2)!);
      i = head.end;
      if (i < s.length && (s.codeUnitAt(i) == 10 || s.codeUnitAt(i) == 13)) {
        i++;
        if (i < s.length && s.codeUnitAt(i) == 10) i++;
      }
      for (var n = 0; n < count; n++) {
        if (i + 18 > s.length) break;
        final line = s.substring(i, math.min(s.length, i + 20));
        final entry = RegExp(r'(\d{10})\s+(\d{5})\s+([nf])').firstMatch(line);
        if (entry != null && entry.group(3) == 'n') {
          final objNum = startNum + n;
          xref.putIfAbsent(objNum, () => int.parse(entry.group(1)!));
        }
        i += 20;
      }
    }
    final trailerAt = s.indexOf('trailer', offset);
    if (trailerAt >= 0) {
      final c = _C(s, trailerAt + 'trailer'.length);
      final v = c.parse();
      final dict = v?.dict;
      if (dict != null) {
        root ??= dict['/Root']?.ref;
        prev = dict['/Prev']?.number?.toInt();
      }
    }
    if (prev != null) _readXref(prev);
  }

  void _readXrefStream(int offset) {
    final obj = _parseObjAt(offset);
    if (obj == null) return;
    final dict = obj.dict;
    root ??= dict['/Root']?.ref;
    final w = dict['/W']?.array;
    if (w == null || w.length < 3 || obj.stream == null) return;
    final w0 = w[0].number?.toInt() ?? 1;
    final w1 = w[1].number?.toInt() ?? 2;
    final w2 = w[2].number?.toInt() ?? 1;
    var data = _decodeStream(dict, obj.stream!);
    final index = dict['/Index']?.array;
    final ranges = <(int, int)>[];
    if (index != null && index.length >= 2) {
      for (var i = 0; i + 1 < index.length; i += 2) {
        ranges.add((
          index[i].number?.toInt() ?? 0,
          index[i + 1].number?.toInt() ?? 0,
        ));
      }
    } else {
      ranges.add((0, dict['/Size']?.number?.toInt() ?? 0));
    }
    final width = w0 + w1 + w2;
    var p = 0;
    for (final range in ranges) {
      for (var n = 0; n < range.$2; n++) {
        if (p + width > data.length) return;
        final type = w0 == 0 ? 1 : _be(data, p, w0);
        final f1 = _be(data, p + w0, w1);
        final f2 = _be(data, p + w0 + w1, w2);
        p += width;
        final objNum = range.$1 + n;
        if (type == 1) {
          xref.putIfAbsent(objNum, () => f1);
        } else if (type == 2) {
          compressed.putIfAbsent(objNum, () => (f1, f2));
        }
      }
    }
    final prev = dict['/Prev']?.number?.toInt();
    if (prev != null) _readXref(prev);
  }

  void _scanObjects() {
    final re = RegExp(r'(\d+)\s+\d+\s+obj');
    for (final m in re.allMatches(s)) {
      final num = int.parse(m.group(1)!);
      xref.putIfAbsent(num, () => m.start);
      if (root == null && s.substring(m.end, math.min(s.length, m.end + 400)).contains('/Type /Catalog')) {
        root = num;
      }
      if (root == null && s.substring(m.end, math.min(s.length, m.end + 400)).contains('/Type/Catalog')) {
        root = num;
      }
    }
  }

  void _walkPages(
    int objNum,
    Map<String, _V>? inheritedRes,
    List<double>? inheritedBox,
    List<_PageInfo> out,
    int depth,
    List<double>? inheritedCrop,
    int inheritedRotate,
  ) {
    if (depth > 40 || out.length > 500) return;
    final obj = _load(objNum);
    final d = obj.dict;
    final box = _nums(d['/MediaBox']) ?? inheritedBox;
    final crop = _nums(d['/CropBox']) ?? inheritedCrop;
    final rotate = d['/Rotate']?.number?.round() ?? inheritedRotate;
    final resVal = d['/Resources'];
    final res = resVal == null ? inheritedRes : _asDict(resVal);
    final type = d['/Type']?.name;
    final isPage = type == '/Page' || (type != '/Pages' && d.containsKey('/Contents'));
    if (isPage && type != '/Pages') {
      final media = box ?? const <double>[0, 0, 612, 792];
      // The renderer shows the CropBox (clipped to the MediaBox), turned by
      // /Rotate; word boxes are given for that displayed page.
      out.add(_PageInfo(d, res, crop != null && crop.length == 4 ? crop : media, rotate));
      return;
    }
    final kids = d['/Kids']?.array;
    if (kids == null) return;
    for (final k in kids) {
      final ref = k.ref;
      if (ref != null) _walkPages(ref, res, box, out, depth + 1, crop, rotate);
    }
  }

  List<PdfTextElement> _extractPage(_PageInfo page) {
    final contents = page.dict['/Contents'];
    if (contents == null) return const [];
    final streams = <Uint8List>[];
    void take(_V v) {
      if (v.ref != null) {
        final o = _load(v.ref!);
        if (o.stream != null) streams.add(_decodeStream(o.dict, o.stream!));
      } else if (v.array != null) {
        for (final c in v.array!) {
          take(c);
        }
      }
    }

    take(contents);
    if (streams.isEmpty) return const [];
    final fonts = _fonts(page.resources);
    final box = page.box;
    final llx = box[0] < box[2] ? box[0] : box[2];
    final lly = box[1] < box[3] ? box[1] : box[3];
    final urx = (box[0] < box[2] ? box[2] : box[0]).toDouble();
    final ury = (box[1] < box[3] ? box[3] : box[1]).toDouble();
    final pw = ((urx - llx).abs() < 1 ? 612.0 : (urx - llx)).toDouble();
    final ph = ((ury - lly).abs() < 1 ? 792.0 : (ury - lly)).toDouble();
    final out = <PdfTextElement>[];
    for (final stream in streams) {
      try {
        _readContent(stream, fonts, llx, lly, ury, pw, ph, out, resources: page.resources);
      } catch (_) {}
      if (out.length > 20000) break;
    }
    // Boxes so far are on the unrotated page; turn them as it is shown.
    final turns = (((page.rotate % 360) + 360) % 360) ~/ 90;
    return turns == 0 ? out : [for (final e in out) e.turned(turns)];
  }

  Map<String, _Font> _fonts(Map<String, _V>? resources) {
    final fonts = <String, _Font>{};
    if (resources == null) return fonts;
    final fontDict = _asDict(resources['/Font']);
    if (fontDict == null) return fonts;
    fontDict.forEach((name, value) {
      try {
        fonts[name] = _loadFont(value);
      } catch (_) {
        fonts[name] = _Font();
      }
    });
    return fonts;
  }

  _Font _loadFont(_V v) {
    final obj = v.ref != null ? _load(v.ref!) : _Obj(v, null);
    final d = obj.dict;
    final font = _Font();
    final base = d['/BaseFont']?.name;
    if (base != null) font.baseName = base.startsWith('/') ? base.substring(1) : base;
    final first = d['/FirstChar']?.number?.toInt();
    if (first != null) font.firstChar = first;
    final widths = d['/Widths']?.array ?? (d['/Widths']?.ref != null ? _load(d['/Widths']!.ref!).value.array : null);
    if (widths != null) {
      font.widths = [
        for (final w in widths) w.number ?? 500,
      ];
    }
    final subtype = d['/Subtype']?.name;
    if (subtype == '/Type0') font.twoByte = true;
    final uni = d['/ToUnicode'];
    if (uni?.ref != null) {
      final u = _load(uni!.ref!);
      if (u.stream != null) {
        _parseCMap(_decodeStream(u.dict, u.stream!), font);
      }
    }
    final desc = d['/DescendantFonts']?.array;
    if (desc != null && desc.isNotEmpty) {
      final child = desc.first.ref != null ? _load(desc.first.ref!) : _Obj(desc.first, null);
      final cd = child.dict;
      if (font.unicode.isEmpty && cd['/ToUnicode']?.ref != null) {
        final u = _load(cd['/ToUnicode']!.ref!);
        if (u.stream != null) _parseCMap(_decodeStream(u.dict, u.stream!), font);
      }
      if (font.widths == null) _cidWidths(cd['/W'], font);
    }
    if (font.unicode.keys.any((k) => k > 255)) font.twoByte = true;
    return font;
  }

  void _cidWidths(_V? w, _Font font) {
    if (w == null) return;
    final arr = w.ref != null ? _load(w.ref!).value.array : w.array;
    if (arr == null) return;
    // CID /W : c [w w w] or cfirst clast w
    final map = <int, double>{};
    var i = 0;
    while (i < arr.length) {
      final c = arr[i].number?.toInt();
      if (c == null) {
        i++;
        continue;
      }
      if (i + 1 < arr.length && arr[i + 1].array != null) {
        final list = arr[i + 1].array!;
        for (var k = 0; k < list.length; k++) {
          map[c + k] = list[k].number ?? 500;
        }
        i += 2;
      } else if (i + 2 < arr.length && arr[i + 1].number != null && arr[i + 2].number != null) {
        final last = arr[i + 1].number!.toInt();
        final width = arr[i + 2].number!;
        for (var k = c; k <= last; k++) {
          map[k] = width;
        }
        i += 3;
      } else {
        i++;
      }
    }
    if (map.isEmpty) return;
    final minC = map.keys.reduce(math.min);
    final maxC = map.keys.reduce(math.max);
    if (maxC - minC > 20000) return;
    font.firstChar = minC;
    font.widths = List<double>.generate(maxC - minC + 1, (i) => map[minC + i] ?? 500);
  }

  void _parseCMap(Uint8List data, _Font font) {
    final text = String.fromCharCodes(data);
    final bf = RegExp(r'beginbfchar(.*?)endbfchar', dotAll: true);
    final pair = RegExp(r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>');
    for (final block in bf.allMatches(text)) {
      for (final m in pair.allMatches(block.group(1)!)) {
        final src = int.parse(m.group(1)!, radix: 16);
        font.unicode[src] = _utf(m.group(2)!);
      }
    }
    final br = RegExp(r'beginbfrange(.*?)endbfrange', dotAll: true);
    final rangeDest = RegExp(
      r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
    );
    final rangeArr = RegExp(
      r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[(.*?)\]',
      dotAll: true,
    );
    for (final block in br.allMatches(text)) {
      final body = block.group(1)!;
      for (final m in rangeArr.allMatches(body)) {
        final start = int.parse(m.group(1)!, radix: 16);
        final dests = pair.allMatches(m.group(3)!).map((e) => _utf(e.group(2)!)).toList();
        for (var k = 0; k < dests.length; k++) {
          font.unicode[start + k] = dests[k];
        }
      }
      for (final m in rangeDest.allMatches(body)) {
        final start = int.parse(m.group(1)!, radix: 16);
        final end = int.parse(m.group(2)!, radix: 16);
        final destHex = m.group(3)!;
        if (end < start || end - start > 5000) continue;
        final dest = int.parse(destHex, radix: 16);
        for (var k = 0; k <= end - start; k++) {
          font.unicode[start + k] = _utf((dest + k).toRadixString(16).padLeft(destHex.length, '0'));
        }
      }
    }
  }

  String _utf(String hex) {
    final clean = hex.length.isOdd ? '0$hex' : hex;
    if (clean.length <= 2) {
      return String.fromCharCode(int.parse(clean, radix: 16));
    }
    final units = <int>[];
    for (var i = 0; i + 4 <= clean.length; i += 4) {
      units.add(int.parse(clean.substring(i, i + 4), radix: 16));
    }
    return String.fromCharCodes(units);
  }

  void _readContent(
    Uint8List data,
    Map<String, _Font> fonts,
    double llx,
    double lly,
    double ury,
    double pw,
    double ph,
    List<PdfTextElement> out, {
    Map<String, _V>? resources,
    _M? initialCtm,
    int depth = 0,
    Set<int>? formsInUse,
  }) {
    final text = String.fromCharCodes(data);
    final c = _C(text, 0);
    final stack = <_Tok>[];
    final ctmStack = <_M>[];
    var ctm = initialCtm?.copy() ?? _M.identity();
    final activeForms = formsInUse ?? <int>{};

    // Text inside a Form XObject (`/Name Do`), such as the overlay a
    // source-preserving export adds, is part of the page's text too.
    void drawForm(String name) {
      if (depth >= 8) return;
      final xobjects = _asDict(resources?['/XObject']);
      final ref = xobjects?[name]?.ref;
      if (ref == null || !activeForms.add(ref)) return;
      try {
        final obj = _load(ref);
        if (obj.dict['/Subtype']?.name != '/Form' || obj.stream == null) return;
        final formResources = _asDict(obj.dict['/Resources']) ?? resources;
        final m = _nums6(obj.dict['/Matrix']);
        final formCtm = m == null ? ctm.copy() : _mul(ctm, _M(m[0], m[1], m[2], m[3], m[4], m[5]));
        _readContent(
          _decodeStream(obj.dict, obj.stream!),
          _fonts(formResources),
          llx,
          lly,
          ury,
          pw,
          ph,
          out,
          resources: formResources,
          initialCtm: formCtm,
          depth: depth + 1,
          formsInUse: activeForms,
        );
      } catch (_) {
        // A broken form hides only its own text.
      } finally {
        activeForms.remove(ref);
      }
    }

    var tm = _M.identity();
    var lm = _M.identity();
    var inText = false;
    var font = _Font();
    var fontSize = 12.0;
    var charSpace = 0.0;
    var wordSpace = 0.0;
    var hScale = 100.0;
    var leading = 0.0;

    void translateLine(double tx, double ty) {
      final e = lm.e + tx * lm.a + ty * lm.c;
      final f = lm.f + tx * lm.b + ty * lm.d;
      lm.e = e;
      lm.f = f;
      tm = lm.copy();
    }

    Offset textToUser(double x, double y) {
      final xt = tm.a * x + tm.c * y + tm.e;
      final yt = tm.b * x + tm.d * y + tm.f;
      return Offset(
        ctm.a * xt + ctm.c * yt + ctm.e,
        ctm.b * xt + ctm.d * yt + ctm.f,
      );
    }

    void show(List<int> codes) {
      if (!inText || codes.isEmpty) return;
      final two = font.twoByte && codes.length >= 2;
      final sb = StringBuffer();
      // Each glyph's text and where it starts and ends along the line, so
      // word boxes come from the real widths, not an even split.
      final glyphs = <(String, double, double)>[];
      var advance = 0.0;
      var i = 0;
      while (i < codes.length) {
        int code;
        if (two && i + 1 < codes.length) {
          code = (codes[i] << 8) | codes[i + 1];
          i += 2;
        } else {
          code = codes[i];
          i++;
        }
        final mapped = font.unicode[code];
        final t = mapped ?? (code >= 32 && code < 256 ? String.fromCharCode(code) : '');
        sb.write(t);
        final start = advance;
        var tx = font.widthOf(code) * fontSize + charSpace;
        if (code == 32) tx += wordSpace;
        advance += tx * (hScale / 100.0);
        glyphs.add((t, start, start + font.widthOf(code) * fontSize * (hScale / 100.0)));
      }
      final shown = sb.toString();
      if (shown.trim().isEmpty || advance.abs() < 0.01) {
        _advanceTm(tm, advance);
        return;
      }
      final o = textToUser(0, 0);
      final rgt = textToUser(advance, 0);
      final up = textToUser(0, fontSize);
      final far = textToUser(advance, fontSize);
      final minX = _min4(o.dx, rgt.dx, up.dx, far.dx);
      final maxX = _max4(o.dx, rgt.dx, up.dx, far.dx);
      final minY = _min4(o.dy, rgt.dy, up.dy, far.dy);
      final maxY = _max4(o.dy, rgt.dy, up.dy, far.dy);
      final left = ((minX - llx) / pw).clamp(0.0, 1.0);
      final right = ((maxX - llx) / pw).clamp(0.0, 1.0);
      final top = ((ury - maxY) / ph).clamp(0.0, 1.0);
      final bottom = ((ury - minY) / ph).clamp(0.0, 1.0);
      if (right - left > 0.001 && bottom - top > 0.001) {
        final rect = Rect.fromLTRB(left, top, right, bottom);
        final horizontal = (rgt.dy - o.dy).abs() < 1.5;
        if (horizontal) {
          Rect boxOf(double x0, double x1) {
            final a = textToUser(x0, 0), b = textToUser(x1, 0), c = textToUser(x0, fontSize), d = textToUser(x1, fontSize);
            return Rect.fromLTRB(
              ((_min4(a.dx, b.dx, c.dx, d.dx) - llx) / pw).clamp(0.0, 1.0),
              ((ury - _max4(a.dy, b.dy, c.dy, d.dy)) / ph).clamp(0.0, 1.0),
              ((_max4(a.dx, b.dx, c.dx, d.dx) - llx) / pw).clamp(0.0, 1.0),
              ((ury - _min4(a.dy, b.dy, c.dy, d.dy)) / ph).clamp(0.0, 1.0),
            );
          }

          var i = 0;
          while (i < glyphs.length) {
            while (i < glyphs.length && glyphs[i].$1.trim().isEmpty) {
              i++;
            }
            if (i >= glyphs.length) break;
            final first = i;
            final word = StringBuffer();
            while (i < glyphs.length && glyphs[i].$1.trim().isNotEmpty) {
              word.write(glyphs[i].$1);
              i++;
            }
            final box = boxOf(glyphs[first].$2, glyphs[i - 1].$3);
            if (box.width > 0.0005) out.add(_styled(word.toString(), box, fontSize, font));
          }
        } else {
          out.add(_styled(shown.trim(), rect, fontSize, font));
        }
      }
      _advanceTm(tm, advance);
    }

    while (c.i < text.length) {
      final tok = c.token();
      if (tok == null) break;
      if (tok.op == null) {
        stack.add(tok);
        continue;
      }
      final op = tok.op!;
      switch (op) {
        case 'q':
          ctmStack.add(ctm.copy());
          break;
        case 'Q':
          if (ctmStack.isNotEmpty) ctm = ctmStack.removeLast();
          break;
        case 'cm':
          if (stack.length >= 6) {
            final n = stack.sublist(stack.length - 6);
            stack.removeRange(stack.length - 6, stack.length);
            final m = _M(
              n[0].number ?? 1,
              n[1].number ?? 0,
              n[2].number ?? 0,
              n[3].number ?? 1,
              n[4].number ?? 0,
              n[5].number ?? 0,
            );
            // cm applies the new matrix first, then the current CTM.
            ctm = _mul(ctm, m);
          }
          break;
        case 'BT':
          inText = true;
          tm = _M.identity();
          lm = _M.identity();
          stack.clear();
          break;
        case 'ET':
          inText = false;
          stack.clear();
          break;
        case 'Tm':
          if (stack.length >= 6) {
            final n = stack.sublist(stack.length - 6);
            tm = _M(
              n[0].number ?? 1,
              n[1].number ?? 0,
              n[2].number ?? 0,
              n[3].number ?? 1,
              n[4].number ?? 0,
              n[5].number ?? 0,
            );
            lm = tm.copy();
          }
          stack.clear();
          break;
        case 'Td':
          if (stack.length >= 2) {
            translateLine(stack[stack.length - 2].number ?? 0, stack.last.number ?? 0);
          }
          stack.clear();
          break;
        case 'TD':
          if (stack.length >= 2) {
            leading = -(stack.last.number ?? 0);
            translateLine(stack[stack.length - 2].number ?? 0, stack.last.number ?? 0);
          }
          stack.clear();
          break;
        case 'T*':
          translateLine(0, -leading);
          stack.clear();
          break;
        case 'Tc':
          if (stack.isNotEmpty) charSpace = stack.last.number ?? 0;
          stack.clear();
          break;
        case 'Tw':
          if (stack.isNotEmpty) wordSpace = stack.last.number ?? 0;
          stack.clear();
          break;
        case 'Tz':
          if (stack.isNotEmpty) hScale = stack.last.number ?? 100;
          stack.clear();
          break;
        case 'TL':
          if (stack.isNotEmpty) leading = stack.last.number ?? 0;
          stack.clear();
          break;
        case 'Tf':
          if (stack.length >= 2) {
            final name = stack[stack.length - 2].name;
            fontSize = stack.last.number ?? fontSize;
            if (name != null) font = fonts[name] ?? font;
          }
          stack.clear();
          break;
        case 'Tj':
          if (stack.isNotEmpty && stack.last.codes != null) {
            show(stack.last.codes!);
          }
          stack.clear();
          break;
        case "'":
          translateLine(0, -leading);
          if (stack.isNotEmpty && stack.last.codes != null) show(stack.last.codes!);
          stack.clear();
          break;
        case '"':
          if (stack.length >= 3) {
            wordSpace = stack[stack.length - 3].number ?? wordSpace;
            charSpace = stack[stack.length - 2].number ?? charSpace;
            translateLine(0, -leading);
            final codes = stack.last.codes;
            if (codes != null) show(codes);
          }
          stack.clear();
          break;
        case 'TJ':
          if (stack.isNotEmpty && stack.last.array != null) {
            final codes = <int>[];
            var adjust = 0.0;
            for (final item in stack.last.array!) {
              if (item.codes != null) {
                if (adjust != 0) {
                  // A position adjustment between glyphs: show what we have
                  // so each chunk keeps its own box, then shift.
                  if (codes.isNotEmpty) {
                    show(List<int>.of(codes));
                    codes.clear();
                  }
                  _advanceTm(tm, -adjust / 1000.0 * fontSize * (hScale / 100.0));
                  adjust = 0;
                }
                codes.addAll(item.codes!);
              } else if (item.number != null) {
                adjust += item.number!;
              }
            }
            if (codes.isNotEmpty) show(List<int>.of(codes));
            if (adjust != 0) {
              _advanceTm(tm, -adjust / 1000.0 * fontSize * (hScale / 100.0));
            }
          }
          stack.clear();
          break;
        case 'Do':
          final name = stack.isEmpty ? null : stack.last.name;
          stack.clear();
          if (name != null && !inText) drawForm(name);
          break;
        default:
          stack.clear();
      }
    }
  }

  List<double>? _nums6(_V? v) {
    final a = v?.array ?? (v?.ref != null ? _load(v!.ref!).value.array : null);
    if (a == null || a.length != 6) return null;
    return [for (final n in a) n.number ?? 0];
  }

  void _advanceTm(_M tm, double tx) {
    tm.e = tm.e + tx * tm.a;
    tm.f = tm.f + tx * tm.b;
  }

  PdfTextElement _styled(String text, Rect rect, double fontSize, _Font font) {
    final name = font.baseName.toLowerCase();
    return PdfTextElement(
      text: text,
      rect: rect,
      fontSize: fontSize,
      fontName: font.baseName.isEmpty ? null : font.baseName,
      isBold: name.contains('bold') || name.contains('black'),
      isItalic: name.contains('italic') || name.contains('oblique'),
    );
  }

  _Obj _load(int n) {
    final hit = cache[n];
    if (hit != null) return hit;
    final off = xref[n];
    if (off != null) {
      final obj = _parseObjAt(off) ?? _Obj(const _V.dict({}), null);
      cache[n] = obj;
      return obj;
    }
    final comp = compressed[n];
    if (comp != null) {
      _expandObjStm(comp.$1);
      return cache[n] ?? _Obj(const _V.dict({}), null);
    }
    return _Obj(const _V.dict({}), null);
  }

  void _expandObjStm(int stmNum) {
    if (cache.containsKey(-stmNum)) return;
    final obj = _load(stmNum);
    cache[-stmNum] = obj;
    final n = obj.dict['/N']?.number?.toInt() ?? 0;
    final first = obj.dict['/First']?.number?.toInt() ?? 0;
    if (obj.stream == null || n <= 0) return;
    final data = _decodeStream(obj.dict, obj.stream!);
    final header = String.fromCharCodes(data.sublist(0, math.min(first, data.length)));
    final pairs = header.trim().split(RegExp(r'\s+'));
    final entries = <(int, int)>[];
    for (var i = 0; i + 1 < pairs.length && entries.length < n; i += 2) {
      final num = int.tryParse(pairs[i]);
      final rel = int.tryParse(pairs[i + 1]);
      if (num != null && rel != null) entries.add((num, rel));
    }
    final body = String.fromCharCodes(data);
    for (var i = 0; i < entries.length; i++) {
      final start = first + entries[i].$2;
      final end = i + 1 < entries.length ? first + entries[i + 1].$2 : body.length;
      if (start < 0 || start >= body.length || end <= start) continue;
      final c = _C(body, start);
      final v = c.parse();
      if (v != null) cache[entries[i].$1] = _Obj(v, null);
    }
  }

  _Obj? _parseObjAt(int offset) {
    if (offset < 0 || offset >= s.length) return null;
    final c = _C(s, offset);
    c.skip();
    c.parse(); // object number
    c.parse(); // generation
    c.skip();
    if (s.startsWith('obj', c.i)) c.i += 3;
    final v = c.parse();
    if (v == null) return null;
    c.skip();
    Uint8List? stream;
    if (s.startsWith('stream', c.i)) {
      var start = c.i + 'stream'.length;
      if (start < bytes.length && bytes[start] == 13) start++;
      if (start < bytes.length && bytes[start] == 10) start++;
      var end = s.indexOf('endstream', start);
      if (end < 0) end = bytes.length;
      var sliceEnd = end;
      if (sliceEnd > start && bytes[sliceEnd - 1] == 10) sliceEnd--;
      if (sliceEnd > start && bytes[sliceEnd - 1] == 13) sliceEnd--;
      stream = Uint8List.sublistView(bytes, start, sliceEnd);
    }
    return _Obj(v, stream);
  }

  Uint8List _decodeStream(Map<String, _V> dict, Uint8List data) {
    final filters = <String>[];
    final f = dict['/Filter'];
    if (f?.name != null) filters.add(f!.name!);
    if (f?.array != null) {
      for (final item in f!.array!) {
        if (item.name != null) filters.add(item.name!);
      }
    }
    var cur = data;
    for (final name in filters) {
      if (name == '/FlateDecode' || name == '/Fl') {
        cur = _inflate(cur);
      }
    }
    return cur;
  }

  Uint8List _inflate(Uint8List data) {
    try {
      return Uint8List.fromList(ZLibDecoder().convert(data));
    } catch (_) {
      try {
        return Uint8List.fromList(ZLibDecoder(raw: true).convert(data));
      } catch (_) {
        return data;
      }
    }
  }

  Map<String, _V>? _asDict(_V? v) {
    if (v == null) return null;
    if (v.dict != null) return v.dict;
    if (v.ref != null) return _load(v.ref!).dict;
    return null;
  }

  List<double>? _nums(_V? v) {
    if (v == null) return null;
    if (v.ref != null) return _nums(_load(v.ref!).value);
    final a = v.array;
    if (a == null || a.length < 4) return null;
    return [for (final n in a) n.number ?? 0];
  }

  int _be(Uint8List d, int o, int n) {
    var v = 0;
    for (var i = 0; i < n; i++) {
      v = (v << 8) | d[o + i];
    }
    return v;
  }

  void _skipWsAt(int offset) {}

  bool _ws(int c) => c == 32 || c == 9 || c == 10 || c == 13 || c == 12;
}

class _PageInfo {
  final Map<String, _V> dict;
  final Map<String, _V>? resources;

  /// The displayed area: the CropBox, else the MediaBox.
  final List<double> box;
  final int rotate;
  _PageInfo(this.dict, this.resources, this.box, this.rotate);
}

class _Tok {
  final double? number;
  final String? name;
  final List<int>? codes;
  final List<_Tok>? array;
  final String? op;
  _Tok.number(this.number)
      : name = null,
        codes = null,
        array = null,
        op = null;
  _Tok.name(this.name)
      : number = null,
        codes = null,
        array = null,
        op = null;
  _Tok.codes(this.codes)
      : number = null,
        name = null,
        array = null,
        op = null;
  _Tok.array(this.array)
      : number = null,
        name = null,
        codes = null,
        op = null;
  _Tok.op(this.op)
      : number = null,
        name = null,
        codes = null,
        array = null;
}

class _C {
  final String s;
  int i;
  _C(this.s, this.i);

  void skip() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 37) {
        while (i < s.length && s.codeUnitAt(i) != 10 && s.codeUnitAt(i) != 13) {
          i++;
        }
        continue;
      }
      if (c == 32 || c == 9 || c == 10 || c == 13 || c == 12) {
        i++;
        continue;
      }
      break;
    }
  }

  _V? parse() {
    skip();
    if (i >= s.length) return null;
    if (s.startsWith('<<', i)) return _dict();
    if (s.codeUnitAt(i) == 91) return _array();
    if (s.codeUnitAt(i) == 47) return _V.name(_name());
    if (s.codeUnitAt(i) == 40) return _V.str(_litString());
    if (s.codeUnitAt(i) == 60) return _V.str(_hexString());
    if (_isNumStart(s.codeUnitAt(i))) {
      final n = _number();
      final after = i;
      skip();
      if (i < s.length && _isNumStart(s.codeUnitAt(i))) {
        _number();
        skip();
        if (s.startsWith('R', i) &&
            (i + 1 >= s.length || !_isNameChar(s.codeUnitAt(i + 1)))) {
          i += 1;
          return _V.ref(n.toInt());
        }
        // Not a reference. The second number belongs to the caller.
        i = after;
        return _V.number(n);
      }
      i = after;
      return _V.number(n);
    }
    // keyword
    final start = i;
    while (i < s.length && _isNameChar(s.codeUnitAt(i))) {
      i++;
    }
    if (i == start) {
      i++;
      return null;
    }
    return _V.name(s.substring(start, i));
  }

  _V _dict() {
    i += 2;
    final map = <String, _V>{};
    while (i < s.length) {
      skip();
      if (s.startsWith('>>', i)) {
        i += 2;
        break;
      }
      if (i >= s.length) break;
      if (s.codeUnitAt(i) != 47) {
        i++;
        continue;
      }
      final key = _name();
      final val = parse();
      if (val != null) map[key] = val;
    }
    return _V.dict(map);
  }

  _V _array() {
    i++; // [
    final list = <_V>[];
    while (i < s.length) {
      skip();
      if (i < s.length && s.codeUnitAt(i) == 93) {
        i++;
        break;
      }
      final v = parse();
      if (v == null) {
        if (i < s.length && s.codeUnitAt(i) == 93) {
          i++;
        }
        break;
      }
      list.add(v);
    }
    return _V.array(list);
  }

  String _name() {
    i++; // /
    final start = i;
    while (i < s.length && !_delim(s.codeUnitAt(i))) {
      i++;
    }
    return '/${s.substring(start, i)}';
  }

  String _litString() {
    i++; // (
    final buf = StringBuffer();
    var depth = 1;
    while (i < s.length && depth > 0) {
      final c = s.codeUnitAt(i);
      if (c == 92) {
        i++;
        if (i >= s.length) break;
        final e = s.codeUnitAt(i);
        i++;
        switch (e) {
          case 110:
            buf.write('\n');
            break;
          case 114:
            buf.write('\r');
            break;
          case 116:
            buf.write('\t');
            break;
          default:
            buf.writeCharCode(e);
        }
        continue;
      }
      if (c == 40) depth++;
      if (c == 41) {
        depth--;
        if (depth == 0) {
          i++;
          break;
        }
      }
      buf.writeCharCode(c);
      i++;
    }
    return buf.toString();
  }

  String _hexString() {
    i++; // <
    final start = i;
    while (i < s.length && s.codeUnitAt(i) != 62) {
      i++;
    }
    final hex = s.substring(start, i).replaceAll(RegExp(r'\s'), '');
    if (i < s.length) i++;
    return hex;
  }

  double _number() {
    final start = i;
    if (s.codeUnitAt(i) == 43 || s.codeUnitAt(i) == 45) i++;
    while (i < s.length && s.codeUnitAt(i) >= 48 && s.codeUnitAt(i) <= 57) {
      i++;
    }
    if (i < s.length && s.codeUnitAt(i) == 46) {
      i++;
      while (i < s.length && s.codeUnitAt(i) >= 48 && s.codeUnitAt(i) <= 57) {
        i++;
      }
    }
    return double.tryParse(s.substring(start, i)) ?? 0;
  }

  _Tok? token() {
    skip();
    if (i >= s.length) return null;
    final c = s.codeUnitAt(i);
    if (c == 47) return _Tok.name(_name());
    if (c == 40) return _Tok.codes(_litCodes());
    if (c == 60) {
      if (s.startsWith('<<', i)) {
        // dictionary inside a content stream is rare; skip the dict value
        parse();
        return token();
      }
      return _Tok.codes(_hexCodes());
    }
    if (c == 91) return _Tok.array(_tokArray());
    if (_isNumStart(c)) return _Tok.number(_number());
    final start = i;
    while (i < s.length && !_delim(s.codeUnitAt(i))) {
      i++;
    }
    if (i == start) {
      i++;
      return token();
    }
    return _Tok.op(s.substring(start, i));
  }

  List<_Tok> _tokArray() {
    i++; // [
    final list = <_Tok>[];
    while (i < s.length) {
      skip();
      if (i < s.length && s.codeUnitAt(i) == 93) {
        i++;
        break;
      }
      final t = token();
      if (t == null) break;
      list.add(t);
    }
    return list;
  }

  List<int> _litCodes() {
    i++;
    final out = <int>[];
    var depth = 1;
    while (i < s.length && depth > 0) {
      final c = s.codeUnitAt(i);
      if (c == 92) {
        i++;
        if (i >= s.length) break;
        final e = s.codeUnitAt(i);
        if (e >= 48 && e <= 55) {
          var oct = e - 48;
          i++;
          for (var k = 0; k < 2 && i < s.length; k++) {
            final d = s.codeUnitAt(i);
            if (d < 48 || d > 55) break;
            oct = (oct << 3) | (d - 48);
            i++;
          }
          out.add(oct & 255);
          continue;
        }
        i++;
        switch (e) {
          case 110:
            out.add(10);
            break;
          case 114:
            out.add(13);
            break;
          case 116:
            out.add(9);
            break;
          case 98:
            out.add(8);
            break;
          case 102:
            out.add(12);
            break;
          case 40:
            out.add(40);
            break;
          case 41:
            out.add(41);
            break;
          case 92:
            out.add(92);
            break;
          case 10:
            break;
          case 13:
            if (i < s.length && s.codeUnitAt(i) == 10) i++;
            break;
          default:
            out.add(e);
        }
        continue;
      }
      if (c == 40) depth++;
      if (c == 41) {
        depth--;
        if (depth == 0) {
          i++;
          break;
        }
      }
      out.add(c);
      i++;
    }
    return out;
  }

  List<int> _hexCodes() {
    i++;
    final hex = StringBuffer();
    while (i < s.length && s.codeUnitAt(i) != 62) {
      final c = s.codeUnitAt(i);
      final isHex = (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
      if (isHex) hex.writeCharCode(c);
      i++;
    }
    if (i < s.length) i++;
    var h = hex.toString();
    if (h.length.isOdd) h = '${h}0';
    final out = <int>[];
    for (var k = 0; k + 1 < h.length; k += 2) {
      out.add(int.parse(h.substring(k, k + 2), radix: 16));
    }
    return out;
  }

  bool _isNumStart(int c) =>
      (c >= 48 && c <= 57) || c == 43 || c == 45 || c == 46;

  bool _isNameChar(int c) => !_delim(c);

  bool _delim(int c) =>
      c == 32 ||
      c == 9 ||
      c == 10 ||
      c == 13 ||
      c == 12 ||
      c == 47 ||
      c == 37 ||
      c == 40 ||
      c == 41 ||
      c == 60 ||
      c == 62 ||
      c == 91 ||
      c == 93 ||
      c == 123 ||
      c == 125;
}

double _min4(double a, double b, double c, double d) =>
    math.min(a, math.min(b, math.min(c, d)));
double _max4(double a, double b, double c, double d) =>
    math.max(a, math.max(b, math.max(c, d)));
