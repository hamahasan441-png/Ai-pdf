import 'dart:convert' show latin1;
import 'dart:io' show ZLibCodec, ZLibDecoder;
import 'dart:typed_data';

/// Raw PDF objects read from an existing file, for the source-preserving
/// export. Pure Dart, no Flutter, so it can run in an isolate.
///
/// Reads classic xref tables, xref streams (with PNG predictors), hybrid
/// files (/XRefStm), /Prev chains of incremental updates, and object
/// streams. When the xref cannot be read, objects are found by scanning for
/// `N G obj`. Strings and stream data are kept as raw bytes, so a value is
/// written back exactly as it was read.
///
/// Throws [PdfSourceException] for files it cannot read safely: encrypted
/// files, missing catalog or page tree, and filters other than FlateDecode
/// on xref or object streams.
class PdfObjectStore {
  PdfObjectStore._(this.bytes);

  final Uint8List bytes;

  /// Object number → location. Newest revision wins.
  final Map<int, _Loc> _xref = {};
  final Map<int, PdfIndirect> _cache = {};
  /// Object-stream number → (decoded data, [object number, offset] pairs).
  final Map<int, (Uint8List, List<(int, int)>)> _objStmCache = {};
  late final PdfDict trailer;
  late final String headerVersion;

  /// Every page, in document order, with inherited attributes resolved.
  late final List<PdfPageInfo> pages;

  static PdfObjectStore parse(Uint8List bytes) {
    final store = PdfObjectStore._(bytes);
    store._load();
    return store;
  }

  int get maxObjectNumber {
    var max = 0;
    for (final n in _xref.keys) {
      if (n > max) max = n;
    }
    final size = trailer['/Size'];
    if (size is PdfNum && size.toInt() - 1 > max) max = size.toInt() - 1;
    return max;
  }

  bool get isEncrypted => trailer.containsKey('/Encrypt');

  PdfRef? get rootRef {
    final r = trailer['/Root'];
    return r is PdfRef ? r : null;
  }

  PdfDict get catalog {
    final c = resolve(trailer['/Root']);
    if (c is! PdfDict) throw const PdfSourceException('The PDF has no catalog.');
    return c;
  }

  /// The indirect object [num], or null if it does not exist or cannot be read.
  PdfIndirect? object(int num) {
    final cached = _cache[num];
    if (cached != null) return cached;
    final loc = _xref[num];
    if (loc == null) return null;
    PdfIndirect? obj;
    try {
      obj = loc.inStream ? _readFromObjStm(num, loc) : _readAt(loc.offset, expectNum: num);
    } on PdfSourceException {
      obj = null;
    } on RangeError {
      obj = null;
    } on FormatException {
      obj = null;
    }
    if (obj != null) _cache[num] = obj;
    return obj;
  }

  /// Follow [v] if it is a reference. Missing objects resolve to null.
  PdfValue? resolve(PdfValue? v) {
    var current = v;
    for (var depth = 0; depth < 32 && current is PdfRef; depth++) {
      current = object(current.num)?.value;
    }
    return current is PdfRef ? null : current;
  }

  /// Decoded data of a FlateDecode or unfiltered stream object.
  Uint8List decodeStream(PdfIndirect obj) {
    final data = obj.stream;
    if (data == null) throw const PdfSourceException('Not a stream.');
    return _decode(obj.value as PdfDict, data);
  }

  // ─── Loading ─────────────────────────────────────────────────────────────

  void _load() {
    if (bytes.length < 16) throw const PdfSourceException('The file is too small to be a PDF.');
    final head = latin1.decode(bytes.sublist(0, bytes.length < 1024 ? bytes.length : 1024));
    final m = RegExp(r'%PDF-(\d\.\d)').firstMatch(head);
    if (m == null) throw const PdfSourceException('The file is not a PDF.');
    headerVersion = m.group(1)!;

    PdfDict? trailerDict;
    try {
      trailerDict = _readXrefChain();
    } on PdfSourceException {
      trailerDict = null;
    } on RangeError {
      trailerDict = null;
    } on FormatException {
      trailerDict = null;
    }
    if (trailerDict == null || !_rootReadable(trailerDict)) {
      _xref.clear();
      _cache.clear();
      trailerDict = _reconstruct();
    }
    trailer = trailerDict;
    if (isEncrypted) {
      throw const PdfSourceException('The PDF is encrypted.', encrypted: true);
    }
    pages = _collectPages();
    if (pages.isEmpty) throw const PdfSourceException('The PDF has no pages.');
  }

  bool _rootReadable(PdfDict t) {
    final root = t['/Root'];
    if (root is! PdfRef) return false;
    final v = object(root.num)?.value;
    return v is PdfDict && v['/Pages'] != null;
  }

  int _findStartXref() {
    final tailStart = bytes.length > 2048 ? bytes.length - 2048 : 0;
    final tail = latin1.decode(bytes.sublist(tailStart));
    final idx = tail.lastIndexOf('startxref');
    if (idx < 0) throw const PdfSourceException('No startxref.');
    final m = RegExp(r'startxref\s+(\d+)').matchAsPrefix(tail, idx);
    if (m == null) throw const PdfSourceException('Bad startxref.');
    return int.parse(m.group(1)!);
  }

  PdfDict _readXrefChain() {
    var offset = _findStartXref();
    PdfDict? newest;
    final seen = <int>{};
    while (offset >= 0 && offset < bytes.length && seen.add(offset)) {
      final lex = PdfLexer(bytes, offset);
      lex.skipWhitespace();
      PdfDict section;
      if (lex.peekKeyword('xref')) {
        section = _readXrefTable(lex);
        final stm = section['/XRefStm'];
        if (stm is PdfNum) _readXrefStream(stm.toInt());
      } else {
        section = _readXrefStream(offset);
      }
      newest ??= section;
      final prev = section['/Prev'];
      if (prev is! PdfNum) break;
      offset = prev.toInt();
    }
    if (newest == null) throw const PdfSourceException('No xref.');
    return newest;
  }

  PdfDict _readXrefTable(PdfLexer lex) {
    lex.expectKeyword('xref');
    while (true) {
      lex.skipWhitespace();
      if (lex.peekKeyword('trailer')) break;
      final start = lex.readInt();
      final count = lex.readInt();
      for (var i = 0; i < count; i++) {
        final off = lex.readInt();
        final gen = lex.readInt();
        final kind = lex.readKeyword();
        final num = start + i;
        if (kind == 'n' && !_xref.containsKey(num) && off > 0) {
          _xref[num] = _Loc.direct(off, gen);
        } else if (kind == 'f') {
          _xref.putIfAbsent(num, () => const _Loc.free());
        }
      }
    }
    lex.expectKeyword('trailer');
    final t = lex.readValue();
    if (t is! PdfDict) throw const PdfSourceException('Bad trailer.');
    return t;
  }

  PdfDict _readXrefStream(int offset) {
    final obj = _readAt(offset);
    final dict = obj.value;
    if (dict is! PdfDict || obj.stream == null) throw const PdfSourceException('Bad xref stream.');
    final data = _decode(dict, obj.stream!);
    final w = (dict['/W'] as PdfArray).items.map((e) => (e as PdfNum).toInt()).toList();
    if (w.length != 3) throw const PdfSourceException('Bad /W.');
    final size = (dict['/Size'] as PdfNum).toInt();
    final index = dict['/Index'] is PdfArray
        ? (dict['/Index'] as PdfArray).items.map((e) => (e as PdfNum).toInt()).toList()
        : [0, size];
    final rowLen = w[0] + w[1] + w[2];
    var pos = 0;
    for (var s = 0; s + 1 < index.length; s += 2) {
      for (var i = 0; i < index[s + 1]; i++) {
        if (pos + rowLen > data.length) break;
        int field(int at, int len, int dflt) {
          if (len == 0) return dflt;
          var v = 0;
          for (var k = 0; k < len; k++) {
            v = (v << 8) | data[at + k];
          }
          return v;
        }

        final type = field(pos, w[0], 1);
        final f2 = field(pos + w[0], w[1], 0);
        final f3 = field(pos + w[0] + w[1], w[2], 0);
        pos += rowLen;
        final num = index[s] + i;
        if (_xref.containsKey(num)) continue;
        if (type == 1) {
          _xref[num] = _Loc.direct(f2, f3);
        } else if (type == 2) {
          _xref[num] = _Loc.inStream(f2, f3);
        } else if (type == 0) {
          _xref[num] = const _Loc.free();
        }
      }
    }
    return dict;
  }

  /// Rebuild the xref by scanning for `N G obj`. Later objects win.
  PdfDict _reconstruct() {
    final text = latin1.decode(bytes);
    final re = RegExp(r'(?<![0-9])(\d+)\s+(\d+)\s+obj\b');
    for (final m in re.allMatches(text)) {
      final num = int.parse(m.group(1)!);
      _xref[num] = _Loc.direct(m.start, int.parse(m.group(2)!));
    }
    // Objects inside object streams.
    for (final num in _xref.keys.toList()) {
      final obj = object(num);
      final v = obj?.value;
      if (v is PdfDict && v['/Type'] == const PdfName('/ObjStm') && obj!.stream != null) {
        try {
          final n = (v['/N'] as PdfNum).toInt();
          final data = _decode(v, obj.stream!);
          final lex = PdfLexer(data, 0);
          for (var i = 0; i < n; i++) {
            final inner = lex.readInt();
            lex.readInt();
            _xref.putIfAbsent(inner, () => _Loc.inStream(num, i));
          }
        } catch (_) {
          // An unreadable object stream just contributes nothing.
        }
      }
    }
    PdfDict? trailerDict;
    var at = text.lastIndexOf('trailer');
    if (at >= 0) {
      try {
        final lex = PdfLexer(bytes, at + 7);
        final t = lex.readValue();
        if (t is PdfDict) trailerDict = t;
      } catch (_) {}
    }
    trailerDict ??= const PdfDict({});
    if (!_rootReadable(trailerDict)) {
      for (final num in _xref.keys) {
        final v = object(num)?.value;
        if (v is PdfDict && v['/Type'] == const PdfName('/Catalog') && v['/Pages'] != null) {
          trailerDict = PdfDict({...trailerDict!.entries, '/Root': PdfRef(num, 0)});
          break;
        }
      }
    }
    if (!_rootReadable(trailerDict!)) throw const PdfSourceException('The PDF is damaged.');
    return trailerDict;
  }

  PdfIndirect _readAt(int offset, {int? expectNum}) {
    final lex = PdfLexer(bytes, offset);
    final num = lex.readInt();
    final gen = lex.readInt();
    lex.expectKeyword('obj');
    if (expectNum != null && num != expectNum) {
      throw const PdfSourceException('Xref points at the wrong object.');
    }
    final value = lex.readValue();
    Uint8List? stream;
    lex.skipWhitespace();
    if (value is PdfDict && lex.peekKeyword('stream')) {
      lex.expectKeyword('stream');
      // The data starts after CRLF or LF.
      var start = lex.pos;
      if (start < bytes.length && bytes[start] == 0x0D) start++;
      if (start < bytes.length && bytes[start] == 0x0A) start++;
      final len = resolve(value['/Length']);
      var end = -1;
      if (len is PdfNum) {
        final candidate = start + len.toInt();
        if (candidate <= bytes.length && _endstreamNear(candidate)) end = candidate;
      }
      if (end < 0) end = _scanEndstream(start);
      stream = Uint8List.sublistView(bytes, start, end);
    }
    return PdfIndirect(num, gen, value, stream);
  }

  bool _endstreamNear(int at) {
    final lex = PdfLexer(bytes, at);
    lex.skipWhitespace();
    return lex.peekKeyword('endstream');
  }

  int _scanEndstream(int start) {
    const needle = [0x65, 0x6E, 0x64, 0x73, 0x74, 0x72, 0x65, 0x61, 0x6D]; // endstream
    for (var i = start; i + needle.length <= bytes.length; i++) {
      var ok = true;
      for (var k = 0; k < needle.length; k++) {
        if (bytes[i + k] != needle[k]) {
          ok = false;
          break;
        }
      }
      if (ok) {
        var end = i;
        if (end > start && bytes[end - 1] == 0x0A) end--;
        if (end > start && bytes[end - 1] == 0x0D) end--;
        return end;
      }
    }
    throw const PdfSourceException('Stream without endstream.');
  }

  PdfIndirect? _readFromObjStm(int num, _Loc loc) {
    final (data, entries) = _objStmCache[loc.offset] ?? _loadObjStm(loc.offset);
    // The xref gives the index; fall back to a search if it disagrees.
    var index = loc.gen;
    if (index < 0 || index >= entries.length || entries[index].$1 != num) {
      index = entries.indexWhere((e) => e.$1 == num);
      if (index < 0) return null;
    }
    final value = PdfLexer(data, entries[index].$2).readValue();
    return PdfIndirect(num, 0, value, null);
  }

  (Uint8List, List<(int, int)>) _loadObjStm(int streamNum) {
    final container = object(streamNum);
    final dict = container?.value;
    if (container == null || dict is! PdfDict || container.stream == null) {
      throw const PdfSourceException('Missing object stream.');
    }
    final data = _decode(dict, container.stream!);
    final first = (resolve(dict['/First']) as PdfNum).toInt();
    final n = (resolve(dict['/N']) as PdfNum).toInt();
    final lex = PdfLexer(data, 0);
    final entries = [for (var i = 0; i < n; i++) (lex.readInt(), first + lex.readInt())];
    return _objStmCache[streamNum] = (data, entries);
  }

  Uint8List _decode(PdfDict dict, Uint8List data) {
    final filter = resolve(dict['/Filter']);
    final filters = <String>[];
    if (filter is PdfName) {
      filters.add(filter.name);
    } else if (filter is PdfArray) {
      for (final f in filter.items) {
        final r = resolve(f);
        if (r is PdfName) filters.add(r.name);
      }
    }
    var out = data;
    for (final f in filters) {
      if (f == '/FlateDecode' || f == '/Fl') {
        out = _inflate(out);
      } else {
        throw PdfSourceException('Unsupported stream filter $f.');
      }
    }
    final parms = resolve(dict['/DecodeParms']);
    final p = parms is PdfArray ? (parms.items.isEmpty ? null : resolve(parms.items.first)) : parms;
    if (p is PdfDict) {
      final predictor = resolve(p['/Predictor']);
      if (predictor is PdfNum && predictor.toInt() >= 10) {
        final columns = resolve(p['/Columns']);
        final colors = resolve(p['/Colors']);
        final bpc = resolve(p['/BitsPerComponent']);
        out = _unpredictPng(
          out,
          columns is PdfNum ? columns.toInt() : 1,
          colors is PdfNum ? colors.toInt() : 1,
          bpc is PdfNum ? bpc.toInt() : 8,
        );
      }
    }
    return out;
  }

  static Uint8List _inflate(Uint8List data) {
    try {
      return Uint8List.fromList(ZLibDecoder().convert(data));
    } catch (_) {
      return Uint8List.fromList(ZLibCodec(raw: true).decoder.convert(data));
    }
  }

  static Uint8List _unpredictPng(Uint8List data, int columns, int colors, int bpc) {
    final bpp = ((colors * bpc) / 8).ceil().clamp(1, 16);
    final rowLen = ((columns * colors * bpc) / 8).ceil();
    final out = BytesBuilder(copy: false);
    var prev = Uint8List(rowLen);
    for (var pos = 0; pos + 1 + rowLen <= data.length; pos += rowLen + 1) {
      final type = data[pos];
      final row = Uint8List.fromList(data.sublist(pos + 1, pos + 1 + rowLen));
      for (var i = 0; i < rowLen; i++) {
        final left = i >= bpp ? row[i - bpp] : 0;
        final up = prev[i];
        final upLeft = i >= bpp ? prev[i - bpp] : 0;
        switch (type) {
          case 1:
            row[i] = (row[i] + left) & 0xFF;
          case 2:
            row[i] = (row[i] + up) & 0xFF;
          case 3:
            row[i] = (row[i] + ((left + up) >> 1)) & 0xFF;
          case 4:
            final p = left + up - upLeft;
            final pa = (p - left).abs();
            final pb = (p - up).abs();
            final pc = (p - upLeft).abs();
            final pred = pa <= pb && pa <= pc ? left : (pb <= pc ? up : upLeft);
            row[i] = (row[i] + pred) & 0xFF;
        }
      }
      out.add(row);
      prev = row;
    }
    return out.toBytes();
  }

  List<PdfPageInfo> _collectPages() {
    final result = <PdfPageInfo>[];
    final pagesRef = catalog['/Pages'];
    final visited = <int>{};

    void walk(PdfValue? node, Map<String, PdfValue> inherited, int depth) {
      if (depth > 64 || result.length > 100000) return;
      if (node is PdfRef && !visited.add(node.num)) {
        throw const PdfSourceException('The page tree has a cycle.');
      }
      final dict = resolve(node);
      if (dict is! PdfDict) {
        // A page we cannot read must not quietly disappear from the export.
        throw const PdfSourceException('A page of the PDF could not be read.');
      }
      final next = Map<String, PdfValue>.of(inherited);
      for (final key in PdfPageInfo.inheritable) {
        final v = dict[key];
        if (v != null) next[key] = v;
      }
      final type = dict['/Type'];
      final kids = resolve(dict['/Kids']);
      if (type == const PdfName('/Pages') || (type == null && kids is PdfArray)) {
        if (kids is PdfArray) {
          for (final k in kids.items) {
            walk(k, next, depth + 1);
          }
        }
        return;
      }
      if (node is! PdfRef) {
        throw const PdfSourceException('A page is not an indirect object.');
      }
      result.add(PdfPageInfo(this, node, dict, next));
    }

    walk(pagesRef, const {}, 0);
    final count = resolve((resolve(pagesRef) as PdfDict?)?['/Count']);
    if (count is PdfNum && count.toInt() != result.length) {
      throw const PdfSourceException('The page tree does not match its page count.');
    }
    return result;
  }
}

/// A page as the reader would see it: inherited attributes resolved.
class PdfPageInfo {
  PdfPageInfo(this._store, this.ref, this.dict, this.inherited);

  static const inheritable = ['/Resources', '/MediaBox', '/CropBox', '/Rotate'];

  final PdfObjectStore _store;
  final PdfRef ref;
  final PdfDict dict;
  final Map<String, PdfValue> inherited;

  PdfValue? attr(String key) => dict[key] ?? inherited[key];

  List<double> get mediaBox => _box(attr('/MediaBox')) ?? const [0, 0, 612, 792];

  /// CropBox clipped to MediaBox, as readers show it.
  List<double> get cropBox {
    final media = mediaBox;
    final crop = _box(attr('/CropBox'));
    if (crop == null) return media;
    final x0 = crop[0] > media[0] ? crop[0] : media[0];
    final y0 = crop[1] > media[1] ? crop[1] : media[1];
    final x1 = crop[2] < media[2] ? crop[2] : media[2];
    final y1 = crop[3] < media[3] ? crop[3] : media[3];
    if (x1 <= x0 || y1 <= y0) return media;
    return [x0, y0, x1, y1];
  }

  int get rotate {
    final r = _store.resolve(attr('/Rotate'));
    final v = r is PdfNum ? r.toInt() : 0;
    return ((v % 360) + 360) % 360 ~/ 90 * 90;
  }

  List<double>? _box(PdfValue? v) {
    final r = _store.resolve(v);
    if (r is! PdfArray || r.items.length != 4) return null;
    final nums = <double>[];
    for (final e in r.items) {
      final n = _store.resolve(e);
      if (n is! PdfNum) return null;
      nums.add(n.toDouble());
    }
    return [
      nums[0] < nums[2] ? nums[0] : nums[2],
      nums[1] < nums[3] ? nums[1] : nums[3],
      nums[0] < nums[2] ? nums[2] : nums[0],
      nums[1] < nums[3] ? nums[3] : nums[1],
    ];
  }
}

class PdfSourceException implements Exception {
  final String message;
  final bool encrypted;

  const PdfSourceException(this.message, {this.encrypted = false});

  @override
  String toString() => message;
}

class _Loc {
  final int offset; // file offset, or object-stream number when [inStream]
  final int gen; // generation, or index in the object stream
  final bool inStream;
  final bool free;

  const _Loc.direct(this.offset, this.gen)
      : inStream = false,
        free = false;
  const _Loc.inStream(this.offset, this.gen)
      : inStream = true,
        free = false;
  const _Loc.free()
      : offset = -1,
        gen = 0,
        inStream = false,
        free = true;
}

class PdfIndirect {
  final int num;
  final int gen;
  final PdfValue value;

  /// Raw (still encoded) stream bytes, or null for a non-stream object.
  final Uint8List? stream;

  const PdfIndirect(this.num, this.gen, this.value, this.stream);
}

// ─── Values ──────────────────────────────────────────────────────────────

sealed class PdfValue {
  const PdfValue();
}

/// Numbers keep their source text so they are written back unchanged.
final class PdfNum extends PdfValue {
  final String raw;

  const PdfNum(this.raw);

  factory PdfNum.of(num v) => PdfNum(v is int ? '$v' : _fmt(v.toDouble()));

  double toDouble() => double.tryParse(raw) ?? 0;
  int toInt() => toDouble().round();

  static String _fmt(double v) {
    var s = v.toStringAsFixed(4);
    if (s.contains('.')) s = s.replaceFirst(RegExp(r'\.?0+$'), '');
    return s == '-0' ? '0' : s;
  }

  @override
  bool operator ==(Object other) => other is PdfNum && other.raw == raw;
  @override
  int get hashCode => raw.hashCode;
}

final class PdfName extends PdfValue {
  /// With the leading slash and any #xx escapes, as in the file.
  final String name;

  const PdfName(this.name);

  @override
  bool operator ==(Object other) => other is PdfName && other.name == name;
  @override
  int get hashCode => name.hashCode;
}

/// A literal or hex string, raw bytes including the delimiters.
final class PdfString extends PdfValue {
  final Uint8List raw;

  const PdfString(this.raw);
}

final class PdfBool extends PdfValue {
  final bool value;

  const PdfBool(this.value);
}

final class PdfNull extends PdfValue {
  const PdfNull();
}

final class PdfArray extends PdfValue {
  final List<PdfValue> items;

  const PdfArray(this.items);
}

final class PdfDict extends PdfValue {
  final Map<String, PdfValue> entries;

  const PdfDict(this.entries);

  PdfValue? operator [](String key) => entries[key];
  bool containsKey(String key) => entries.containsKey(key);
}

final class PdfRef extends PdfValue {
  final int num;
  final int gen;

  const PdfRef(this.num, this.gen);

  @override
  bool operator ==(Object other) => other is PdfRef && other.num == num && other.gen == gen;
  @override
  int get hashCode => Object.hash(num, gen);
}

// ─── Lexer ───────────────────────────────────────────────────────────────

class PdfLexer {
  PdfLexer(this.data, this.pos);

  final Uint8List data;
  int pos;

  static bool isWhite(int c) => c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;
  static bool isDelim(int c) =>
      c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D ||
      c == 0x7B || c == 0x7D || c == 0x2F || c == 0x25;

  void skipWhitespace() {
    while (pos < data.length) {
      final c = data[pos];
      if (isWhite(c)) {
        pos++;
      } else if (c == 0x25) {
        while (pos < data.length && data[pos] != 10 && data[pos] != 13) {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  bool peekKeyword(String word) {
    if (pos + word.length > data.length) return false;
    for (var i = 0; i < word.length; i++) {
      if (data[pos + i] != word.codeUnitAt(i)) return false;
    }
    final after = pos + word.length;
    return after >= data.length || isWhite(data[after]) || isDelim(data[after]);
  }

  void expectKeyword(String word) {
    skipWhitespace();
    if (!peekKeyword(word)) throw FormatException('Expected $word at $pos');
    pos += word.length;
  }

  String readKeyword() {
    skipWhitespace();
    final start = pos;
    while (pos < data.length && !isWhite(data[pos]) && !isDelim(data[pos])) {
      pos++;
    }
    if (start == pos) throw FormatException('Expected keyword at $pos');
    return latin1.decode(data.sublist(start, pos));
  }

  int readInt() {
    final k = readKeyword();
    final v = int.tryParse(k);
    if (v == null) throw FormatException('Expected integer at $pos');
    return v;
  }

  PdfValue readValue([int depth = 0]) {
    if (depth > 200) throw const FormatException('Nesting too deep');
    skipWhitespace();
    if (pos >= data.length) throw const FormatException('Unexpected end');
    final c = data[pos];
    if (c == 0x3C && pos + 1 < data.length && data[pos + 1] == 0x3C) {
      pos += 2;
      final map = <String, PdfValue>{};
      while (true) {
        skipWhitespace();
        if (pos + 1 < data.length && data[pos] == 0x3E && data[pos + 1] == 0x3E) {
          pos += 2;
          return PdfDict(map);
        }
        final key = readValue(depth + 1);
        if (key is! PdfName) throw FormatException('Dict key is not a name at $pos');
        skipWhitespace();
        if (pos + 1 < data.length && data[pos] == 0x3E && data[pos + 1] == 0x3E) {
          map[key.name] = const PdfNull();
          continue;
        }
        map[key.name] = readValue(depth + 1);
      }
    }
    if (c == 0x3C) {
      final start = pos;
      final end = data.indexOf(0x3E, pos);
      if (end < 0) throw const FormatException('Unterminated hex string');
      pos = end + 1;
      return PdfString(Uint8List.fromList(data.sublist(start, pos)));
    }
    if (c == 0x28) {
      final start = pos;
      var nest = 0;
      while (pos < data.length) {
        final ch = data[pos];
        if (ch == 0x5C) {
          pos += 2;
          continue;
        }
        if (ch == 0x28) nest++;
        if (ch == 0x29) {
          nest--;
          if (nest == 0) {
            pos++;
            return PdfString(Uint8List.fromList(data.sublist(start, pos)));
          }
        }
        pos++;
      }
      throw const FormatException('Unterminated string');
    }
    if (c == 0x5B) {
      pos++;
      final items = <PdfValue>[];
      while (true) {
        skipWhitespace();
        if (pos < data.length && data[pos] == 0x5D) {
          pos++;
          return PdfArray(items);
        }
        items.add(readValue(depth + 1));
      }
    }
    if (c == 0x2F) {
      final start = pos;
      pos++;
      while (pos < data.length && !isWhite(data[pos]) && !isDelim(data[pos])) {
        pos++;
      }
      return PdfName(latin1.decode(data.sublist(start, pos)));
    }
    final word = readKeyword();
    if (word == 'true') return const PdfBool(true);
    if (word == 'false') return const PdfBool(false);
    if (word == 'null') return const PdfNull();
    if (RegExp(r'^[+-]?(\d+\.?\d*|\.\d+)$').hasMatch(word)) {
      // N G R is a reference.
      if (RegExp(r'^\d+$').hasMatch(word)) {
        final save = pos;
        try {
          skipWhitespace();
          final second = readKeyword();
          if (RegExp(r'^\d+$').hasMatch(second)) {
            skipWhitespace();
            if (peekKeyword('R')) {
              pos++;
              return PdfRef(int.parse(word), int.parse(second));
            }
          }
        } on FormatException {
          // Not a reference.
        }
        pos = save;
      }
      return PdfNum(word);
    }
    throw FormatException('Unexpected token "$word" at $pos');
  }
}

// ─── Writing values ──────────────────────────────────────────────────────

/// Serialise [v]. [mapRef] may rename or drop (return null) references.
void writePdfValue(BytesBuilder out, PdfValue v, PdfRef? Function(PdfRef ref) mapRef) {
  switch (v) {
    case PdfNum(:final raw):
      out.add(latin1.encode(raw));
    case PdfName(:final name):
      out.add(latin1.encode(name));
    case PdfString(:final raw):
      out.add(raw);
    case PdfBool(:final value):
      out.add(latin1.encode(value ? 'true' : 'false'));
    case PdfNull():
      out.add(latin1.encode('null'));
    case PdfRef():
      final mapped = mapRef(v);
      out.add(latin1.encode(mapped == null ? 'null' : '${mapped.num} ${mapped.gen} R'));
    case PdfArray(:final items):
      out.addByte(0x5B);
      for (var i = 0; i < items.length; i++) {
        if (i > 0) out.addByte(0x20);
        writePdfValue(out, items[i], mapRef);
      }
      out.addByte(0x5D);
    case PdfDict(:final entries):
      out.add(latin1.encode('<<'));
      for (final e in entries.entries) {
        out.add(latin1.encode(e.key));
        out.addByte(0x20);
        writePdfValue(out, e.value, mapRef);
        out.addByte(0x0A);
      }
      out.add(latin1.encode('>>'));
  }
}
