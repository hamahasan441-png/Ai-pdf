import 'dart:convert' show latin1;
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';

/// One page of the output document.
sealed class OutputPageSpec {
  const OutputPageSpec();
}

/// Keep a page of the source PDF: its text, vectors, images, links,
/// annotations and form widgets. [overlayPage] is a page of the generated
/// overlay PDF drawn on top (the user's marks), or null.
final class SourcePageSpec extends OutputPageSpec {
  final int sourceIndex;
  final int quarterTurns;
  final int? overlayPage;

  const SourcePageSpec(this.sourceIndex, {this.quarterTurns = 0, this.overlayPage});
}

/// Use a page of the generated PDF as is (an inserted page, or a page
/// flattened to an image so covered content is gone).
final class GeneratedPageSpec extends OutputPageSpec {
  final int generatedPage;

  /// The source page this one replaces (a flattened page). Bookmarks and
  /// links that pointed at that page then point here.
  final int? replacesSource;

  const GeneratedPageSpec(this.generatedPage, {this.replacesSource});
}

/// What the writer kept and dropped, for the caller to report.
class PreservingWriteReport {
  final int keptSourcePages;
  final int generatedPages;
  final int droppedAnnotations;
  final int droppedFormFields;
  final bool pageLabelsDropped;

  const PreservingWriteReport({
    required this.keptSourcePages,
    required this.generatedPages,
    required this.droppedAnnotations,
    required this.droppedFormFields,
    required this.pageLabelsDropped,
  });
}

/// Writes a new PDF that keeps the source objects of every kept page.
///
/// This is a full rewrite, not an incremental update: only objects reachable
/// from the new catalog are written, so a deleted page, a page replaced by a
/// flattened image, and every earlier revision of the file are not in the
/// output. Kept objects keep their object numbers. References to removed
/// pages become null; form fields whose widgets were only on removed pages
/// are dropped with them, so their values are not carried over.
///
/// Annotations on a duplicated page are not copied (they belong to the first
/// copy). Page labels are dropped when the page order changed, because they
/// are indexed by position.
class PreservingPdfWriter {
  PreservingPdfWriter(this.source, this.generated);

  final PdfObjectStore source;
  final PdfObjectStore? generated;

  late int _next;
  final Map<int, _OutObject> _out = {};
  final Map<int, PdfValue> _overrides = {};
  final Set<int> _removed = {};

  /// Removed source page number → the generated page that replaces it.
  final Map<int, int> _replacement = {};
  final Map<int, int> _genMap = {};
  final List<int> _genQueue = [];
  final List<int> _srcQueue = [];

  PreservingWriteReport? report;

  Uint8List write(List<OutputPageSpec> pages) {
    if (pages.isEmpty) throw const PdfSourceException('Nothing to export.');
    _next = source.maxObjectNumber + 1;
    final pagesRoot = _alloc();

    // Which source page objects survive, and which slots are duplicates.
    final keptFirst = <int>{};
    final keptPageNums = <int>{};
    for (final spec in pages) {
      if (spec is SourcePageSpec) {
        _checkSourceIndex(spec.sourceIndex);
        if (keptFirst.add(spec.sourceIndex)) keptPageNums.add(source.pages[spec.sourceIndex].ref.num);
      } else if (spec is GeneratedPageSpec && generated == null) {
        throw const PdfSourceException('No generated pages to import.');
      }
    }
    final removedPages = <int>{
      for (final p in source.pages)
        if (!keptPageNums.contains(p.ref.num)) p.ref.num,
    };
    _removed.addAll(removedPages);

    // Annotations of removed pages, and the form fields that only they hold.
    final removedAnnots = <int>{};
    for (final p in source.pages) {
      if (!removedPages.contains(p.ref.num)) continue;
      final annots = source.resolve(p.dict['/Annots']);
      if (annots is PdfArray) {
        for (final a in annots.items) {
          if (a is PdfRef) removedAnnots.add(a.num);
        }
      }
    }
    _removed.addAll(removedAnnots);
    final droppedFields = _pruneFields();

    // Page objects.
    final kids = <PdfValue>[];
    final seen = <int>{};
    var generatedCount = 0;
    for (final spec in pages) {
      switch (spec) {
        case SourcePageSpec():
          final info = source.pages[spec.sourceIndex];
          final first = seen.add(spec.sourceIndex);
          final num = first ? info.ref.num : _alloc();
          var dict = _sourcePageDict(info, spec, pagesRoot, duplicate: !first);
          if (!first) dict = _withCopiedAnnots(dict, info, num);
          _overrides[num] = dict;
          kids.add(PdfRef(num, first ? info.ref.gen : 0));
        case GeneratedPageSpec():
          generatedCount++;
          final num = _alloc();
          _overrides[num] = _generatedPageDict(spec.generatedPage, pagesRoot);
          kids.add(PdfRef(num, 0));
          final replaced = spec.replacesSource;
          if (replaced != null && replaced >= 0 && replaced < source.pages.length) {
            final pageNum = source.pages[replaced].ref.num;
            if (_removed.contains(pageNum)) _replacement.putIfAbsent(pageNum, () => num);
          }
      }
    }
    _overrides[pagesRoot] = PdfDict({
      '/Type': const PdfName('/Pages'),
      '/Kids': PdfArray(kids),
      '/Count': PdfNum.of(kids.length),
    });

    // Catalog, same object number as before.
    final rootRef = source.rootRef!;
    final catalog = Map<String, PdfValue>.of(source.catalog.entries);
    catalog['/Pages'] = PdfRef(pagesRoot, 0);
    final reordered = !_isIdentity(pages);
    var labelsDropped = false;
    if (reordered && catalog.remove('/PageLabels') != null) labelsDropped = true;
    final open = source.resolve(catalog['/OpenAction']);
    if (open is PdfArray && open.items.isNotEmpty) {
      final target = open.items.first;
      if (target is PdfRef && _removed.contains(target.num) && !_replacement.containsKey(target.num)) {
        catalog.remove('/OpenAction');
      }
    }
    _overrides[rootRef.num] = PdfDict(catalog);

    // Walk everything reachable from the trailer and the new objects.
    _srcQueue.add(rootRef.num);
    final info = source.trailer['/Info'];
    if (info is PdfRef) _srcQueue.add(info.num);
    for (final num in _overrides.keys) {
      _srcQueue.add(num);
    }
    _drain();

    report = PreservingWriteReport(
      keptSourcePages: keptPageNums.length,
      generatedPages: generatedCount,
      droppedAnnotations: removedAnnots.length,
      droppedFormFields: droppedFields,
      pageLabelsDropped: labelsDropped,
    );
    return _assemble(rootRef, info is PdfRef && _out.containsKey(info.num) ? info : null);
  }

  void _checkSourceIndex(int i) {
    if (i < 0 || i >= source.pages.length) {
      throw PdfSourceException('Source page ${i + 1} does not exist.');
    }
  }

  bool _isIdentity(List<OutputPageSpec> pages) {
    if (pages.length != source.pages.length) return false;
    for (var i = 0; i < pages.length; i++) {
      final s = pages[i];
      if (s is! SourcePageSpec || s.sourceIndex != i) return false;
    }
    return true;
  }

  int _alloc() => _next++;

  // ─── Pages ─────────────────────────────────────────────────────────────

  PdfDict _sourcePageDict(PdfPageInfo info, SourcePageSpec spec, int parent, {required bool duplicate}) {
    const replaced = {'/Parent', '/Resources', '/MediaBox', '/CropBox', '/Rotate', '/Contents'};
    const notOnDuplicates = {'/Annots', '/StructParents', '/B', '/Tabs'};
    final dict = <String, PdfValue>{
      for (final e in info.dict.entries.entries)
        if (!replaced.contains(e.key) && !(duplicate && notOnDuplicates.contains(e.key))) e.key: e.value,
    };
    dict['/Parent'] = PdfRef(parent, 0);
    final media = info.attr('/MediaBox');
    if (media != null) dict['/MediaBox'] = media;
    final crop = info.attr('/CropBox');
    if (crop != null) dict['/CropBox'] = crop;
    final rotate = (info.rotate + 90 * (spec.quarterTurns % 4)) % 360;
    if (rotate != 0) dict['/Rotate'] = PdfNum.of(rotate);

    final contents = info.attr('/Contents');
    final resources = info.attr('/Resources');
    final overlay = spec.overlayPage;
    if (overlay == null) {
      if (contents != null) dict['/Contents'] = contents;
      if (resources != null) dict['/Resources'] = resources;
      return PdfDict(dict);
    }

    // Original content runs in its own q/Q so its graphics state cannot leak
    // into the overlay; the overlay is a Form XObject drawn after it.
    final formNum = _importOverlayForm(overlay);
    final formBox = _generatedBox(overlay);
    final name = _freeXObjectName(resources);
    final crop4 = info.cropBox;
    final m = overlayMatrix(
      crop: crop4,
      rotate: rotate,
      formWidth: formBox[2] - formBox[0],
      formHeight: formBox[3] - formBox[1],
    );
    final head = _newStream(Uint8List.fromList(latin1.encode('q\n')));
    final tail = _newStream(Uint8List.fromList(latin1.encode(
      'Q\nq ${m.map(_n).join(' ')} cm $name Do Q\n',
    )));
    final items = <PdfValue>[PdfRef(head, 0)];
    final resolvedContents = contents is PdfRef ? source.resolve(contents) : contents;
    if (resolvedContents is PdfArray) {
      items.addAll(resolvedContents.items);
    } else if (contents != null) {
      items.add(contents);
    }
    items.add(PdfRef(tail, 0));
    dict['/Contents'] = PdfArray(items);

    final res = <String, PdfValue>{};
    final resolvedRes = source.resolve(resources);
    if (resolvedRes is PdfDict) res.addAll(resolvedRes.entries);
    final xobjects = <String, PdfValue>{};
    final existing = source.resolve(res['/XObject']);
    if (existing is PdfDict) xobjects.addAll(existing.entries);
    xobjects[name] = PdfRef(formNum, 0);
    res['/XObject'] = PdfDict(xobjects);
    dict['/Resources'] = PdfDict(res);
    return PdfDict(dict);
  }

  /// A duplicated page gets its own copies of the original's annotations.
  /// Form widgets are left out: one field cannot have its value on two pages
  /// without becoming the same field, which would change the form.
  PdfDict _withCopiedAnnots(PdfDict pageDict, PdfPageInfo original, int pageNum) {
    final annots = source.resolve(original.dict['/Annots']);
    if (annots is! PdfArray) return pageDict;
    final copies = <PdfValue>[];
    for (final a in annots.items) {
      final dict = source.resolve(a);
      if (dict is! PdfDict) continue;
      final subtype = dict['/Subtype'];
      if (subtype == const PdfName('/Widget') || subtype == const PdfName('/Popup')) continue;
      final copy = <String, PdfValue>{
        for (final e in dict.entries.entries)
          if (e.key != '/Popup' && e.key != '/IRT' && e.key != '/Parent') e.key: e.value,
      };
      copy['/P'] = PdfRef(pageNum, 0);
      final num = _alloc();
      _overrides[num] = PdfDict(copy);
      copies.add(PdfRef(num, 0));
    }
    if (copies.isEmpty) return pageDict;
    return PdfDict({...pageDict.entries, '/Annots': PdfArray(copies)});
  }

  PdfDict _generatedPageDict(int pageIndex, int parent) {
    final g = generated!;
    if (pageIndex < 0 || pageIndex >= g.pages.length) {
      throw PdfSourceException('Generated page ${pageIndex + 1} does not exist.');
    }
    final info = g.pages[pageIndex];
    final dict = <String, PdfValue>{
      '/Type': const PdfName('/Page'),
      '/Parent': PdfRef(parent, 0),
      '/MediaBox': PdfArray([for (final v in info.mediaBox) PdfNum.of(v)]),
    };
    final contents = info.attr('/Contents');
    if (contents != null) dict['/Contents'] = _importValue(contents);
    final resources = info.attr('/Resources');
    if (resources != null) dict['/Resources'] = _importValue(resources);
    if (info.rotate != 0) dict['/Rotate'] = PdfNum.of(info.rotate);
    return PdfDict(dict);
  }

  List<double> _generatedBox(int pageIndex) {
    final g = generated;
    if (g == null || pageIndex < 0 || pageIndex >= g.pages.length) {
      throw PdfSourceException('Overlay page ${pageIndex + 1} does not exist.');
    }
    return g.pages[pageIndex].mediaBox;
  }

  /// The overlay page's content as one Form XObject in the output.
  int _importOverlayForm(int pageIndex) {
    final g = generated!;
    final info = g.pages[pageIndex];
    final box = info.mediaBox;
    final content = BytesBuilder(copy: false);
    final contents = g.resolve(info.attr('/Contents'));
    final parts = contents is PdfArray ? contents.items : [info.attr('/Contents')];
    for (final part in parts) {
      if (part is! PdfRef) continue;
      final obj = g.object(part.num);
      if (obj == null || obj.stream == null) {
        throw const PdfSourceException('Overlay content could not be read.');
      }
      content.add(g.decodeStream(obj));
      content.addByte(0x0A);
    }
    final data = Uint8List.fromList(ZLibEncoder().convert(content.toBytes()));
    final resources = info.attr('/Resources');
    final num = _alloc();
    _out[num] = _OutObject(
      num,
      0,
      PdfDict({
        '/Type': const PdfName('/XObject'),
        '/Subtype': const PdfName('/Form'),
        '/BBox': PdfArray([for (final v in box) PdfNum.of(v)]),
        if (resources != null) '/Resources': _importValue(resources),
        '/Filter': const PdfName('/FlateDecode'),
        '/Length': PdfNum.of(data.length),
      }),
      data,
      mapped: true,
    );
    return num;
  }

  String _freeXObjectName(PdfValue? resources) {
    final res = source.resolve(resources);
    final xo = res is PdfDict ? source.resolve(res['/XObject']) : null;
    final taken = xo is PdfDict ? xo.entries.keys.toSet() : <String>{};
    var i = 0;
    while (taken.contains('/PdoczyOverlay$i')) {
      i++;
    }
    return '/PdoczyOverlay$i';
  }

  int _newStream(Uint8List data) {
    final num = _alloc();
    _out[num] = _OutObject(num, 0, PdfDict({'/Length': PdfNum.of(data.length)}), data, mapped: true);
    return num;
  }

  // ─── Form fields ───────────────────────────────────────────────────────

  /// Mark fields whose widgets are all removed. Returns how many fields
  /// (terminal or parent) were dropped.
  int _pruneFields() {
    final acro = source.resolve(source.catalog['/AcroForm']);
    if (acro is! PdfDict) return 0;
    final fields = source.resolve(acro['/Fields']);
    if (fields is! PdfArray) return 0;
    var dropped = 0;

    // True if the field at [ref] has nothing left.
    bool prune(PdfValue node, int depth) {
      if (node is! PdfRef || depth > 32) return false;
      if (_removed.contains(node.num)) return true;
      final dict = source.resolve(node);
      if (dict is! PdfDict) return false;
      final kids = source.resolve(dict['/Kids']);
      if (kids is! PdfArray || kids.items.isEmpty) return false;
      var allGone = true;
      for (final k in kids.items) {
        if (!prune(k, depth + 1)) allGone = false;
      }
      if (allGone) {
        _removed.add(node.num);
        dropped++;
      }
      return allGone;
    }

    for (final f in fields.items) {
      if (f is PdfRef && !_removed.contains(f.num)) {
        prune(f, 0);
      }
    }
    // Widgets that are also terminal fields count as dropped fields.
    for (final f in fields.items) {
      if (f is PdfRef && _removed.contains(f.num)) {
        final d = source.resolve(f);
        if (d is PdfDict && d.containsKey('/FT') && !d.containsKey('/Kids')) dropped++;
      }
    }
    return dropped;
  }

  // ─── Graph walk ────────────────────────────────────────────────────────

  PdfRef? _mapSource(PdfRef ref) {
    final replacement = _replacement[ref.num];
    if (replacement != null) return PdfRef(replacement, 0);
    if (_removed.contains(ref.num)) return null;
    if (_overrides.containsKey(ref.num) || _out.containsKey(ref.num)) return ref;
    final obj = source.object(ref.num);
    if (obj == null) return null; // a dangling reference stays dangling
    _srcQueue.add(ref.num);
    return PdfRef(ref.num, obj.gen);
  }

  void _drain() {
    while (_srcQueue.isNotEmpty || _genQueue.isNotEmpty) {
      while (_srcQueue.isNotEmpty) {
        final num = _srcQueue.removeLast();
        if (_out.containsKey(num)) continue;
        final override = _overrides[num];
        if (override != null) {
          final gen = source.object(num)?.gen ?? 0;
          _out[num] = _OutObject(num, gen, override, null);
          _collectRefs(override);
          continue;
        }
        if (_removed.contains(num)) continue;
        final obj = source.object(num);
        if (obj == null) continue;
        final v = obj.value;
        if (v is PdfDict) {
          final type = v['/Type'];
          if (type == const PdfName('/XRef') || type == const PdfName('/ObjStm')) continue;
        }
        _out[num] = _OutObject(num, obj.gen, v, obj.stream);
        _collectRefs(v);
      }
      while (_genQueue.isNotEmpty) {
        final gNum = _genQueue.removeLast();
        final newNum = _genMap[gNum]!;
        if (_out.containsKey(newNum)) continue;
        final obj = generated!.object(gNum);
        if (obj == null) continue;
        _out[newNum] = _OutObject(newNum, 0, _importValue(obj.value), obj.stream, mapped: true);
      }
    }
  }

  void _collectRefs(PdfValue v) {
    switch (v) {
      case PdfRef():
        _mapSource(v);
      case PdfArray(:final items):
        for (final i in items) {
          _collectRefs(i);
        }
      case PdfDict(:final entries):
        for (final e in entries.values) {
          _collectRefs(e);
        }
      default:
    }
  }

  /// Copy a value from the generated PDF, renumbering its references.
  PdfValue _importValue(PdfValue v) {
    switch (v) {
      case PdfRef():
        final mapped = _genMap.putIfAbsent(v.num, () {
          _genQueue.add(v.num);
          return _alloc();
        });
        return PdfRef(mapped, 0);
      case PdfArray(:final items):
        return PdfArray([for (final i in items) _importValue(i)]);
      case PdfDict(:final entries):
        return PdfDict({for (final e in entries.entries) e.key: _importValue(e.value)});
      default:
        return v;
    }
  }

  // ─── Output ────────────────────────────────────────────────────────────

  Uint8List _assemble(PdfRef root, PdfRef? info) {
    final out = BytesBuilder(copy: false);
    final version = double.tryParse(source.headerVersion) ?? 1.4;
    out.add(latin1.encode('%PDF-${version > 1.7 ? source.headerVersion : '1.7'}\n'));
    out.add(const [0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
    final nums = _out.keys.toList()..sort();
    final offsets = <int, int>{};
    PdfRef? mapSrc(PdfRef r) {
      final replacement = _replacement[r.num];
      if (replacement != null) return PdfRef(replacement, 0);
      if (_removed.contains(r.num)) return null;
      final o = _out[r.num];
      return o == null ? null : PdfRef(r.num, o.gen);
    }

    PdfRef? identity(PdfRef r) => r;
    for (final num in nums) {
      final o = _out[num]!;
      offsets[num] = out.length;
      out.add(latin1.encode('$num ${o.gen} obj\n'));
      final mapper = o.mapped ? identity : mapSrc;
      var value = o.value;
      if (o.stream != null && value is PdfDict) {
        value = PdfDict({...value.entries, '/Length': PdfNum.of(o.stream!.length)});
      }
      writePdfValue(out, _dropRemovedFromLists(value, mapper), mapper);
      if (o.stream != null) {
        out.add(latin1.encode('\nstream\n'));
        out.add(o.stream!);
        out.add(latin1.encode('\nendstream'));
      }
      out.add(latin1.encode('\nendobj\n'));
    }
    final size = (nums.isEmpty ? 0 : nums.last) + 1;
    final xref = out.length;
    final x = StringBuffer('xref\n0 $size\n0000000000 65535 f \n');
    for (var n = 1; n < size; n++) {
      final off = offsets[n];
      if (off == null) {
        x.write('0000000000 00000 f \n');
      } else {
        x.write('${off.toString().padLeft(10, '0')} ${_out[n]!.gen.toString().padLeft(5, '0')} n \n');
      }
    }
    out.add(latin1.encode(x.toString()));
    final trailer = <String, PdfValue>{
      '/Size': PdfNum.of(size),
      '/Root': PdfRef(root.num, _out[root.num]!.gen),
      if (info != null) '/Info': PdfRef(info.num, _out[info.num]!.gen),
    };
    final id = source.trailer['/ID'];
    if (id is PdfArray) trailer['/ID'] = id;
    out.add(latin1.encode('trailer\n'));
    writePdfValue(out, PdfDict(trailer), identity);
    out.add(latin1.encode('\nstartxref\n$xref\n%%EOF\n'));
    return out.toBytes();
  }

  static String _n(double v) => PdfNum.of(v).raw;

  /// Lists of objects (form fields, widget kids, annotations) lose entries
  /// that point at removed objects instead of keeping a null in their place.
  static const _objectLists = {'/Fields', '/Kids', '/Annots', '/CO'};

  bool _deadDest(PdfValue? dest, PdfRef? Function(PdfRef) mapper) {
    if (dest is! PdfArray || dest.items.isEmpty) return false;
    final page = dest.items.first;
    return page is PdfRef && mapper(page) == null;
  }

  PdfValue _dropRemovedFromLists(PdfValue v, PdfRef? Function(PdfRef) mapper) {
    if (v is! PdfDict) return v;
    var changed = false;
    final entries = <String, PdfValue>{};
    for (final e in v.entries.entries) {
      final value = e.value;
      // A destination on a deleted page would send the reader to the wrong
      // page (a null page reads as page 1). Drop it; the bookmark stays.
      if ((e.key == '/Dest' || e.key == '/D') && _deadDest(value, mapper)) {
        changed = true;
        continue;
      }
      if (e.key == '/A' && value is PdfDict && _deadDest(value['/D'], mapper)) {
        changed = true;
        continue;
      }
      if (_objectLists.contains(e.key) && value is PdfArray) {
        final kept = [
          for (final item in value.items)
            if (item is! PdfRef || mapper(item) != null) _dropRemovedFromLists(item, mapper),
        ];
        if (kept.length != value.items.length) changed = true;
        entries[e.key] = PdfArray(kept);
      } else if (value is PdfDict) {
        final inner = _dropRemovedFromLists(value, mapper);
        if (!identical(inner, value)) changed = true;
        entries[e.key] = inner;
      } else {
        entries[e.key] = value;
      }
    }
    return changed ? PdfDict(entries) : v;
  }
}

class _OutObject {
  final int num;
  final int gen;
  final PdfValue value;
  final Uint8List? stream;

  /// References in [value] are already output numbers.
  final bool mapped;

  _OutObject(this.num, this.gen, this.value, this.stream, {this.mapped = false});
}

/// Matrix taking overlay coordinates (origin at the bottom left of the page
/// as displayed, after /Rotate) to the page's unrotated user space.
///
/// [crop] is [x0, y0, x1, y1]; [rotate] is the page's final /Rotate. The
/// overlay is [formWidth] × [formHeight] points and is scaled to the
/// displayed page if the sizes differ slightly.
List<double> overlayMatrix({
  required List<double> crop,
  required int rotate,
  required double formWidth,
  required double formHeight,
}) {
  final x0 = crop[0];
  final y0 = crop[1];
  final w = crop[2] - crop[0];
  final h = crop[3] - crop[1];
  final r = ((rotate % 360) + 360) % 360;
  final shownW = r == 90 || r == 270 ? h : w;
  final shownH = r == 90 || r == 270 ? w : h;
  final sx = formWidth > 0 ? shownW / formWidth : 1.0;
  final sy = formHeight > 0 ? shownH / formHeight : 1.0;
  final List<double> rot = switch (r) {
    90 => [0, 1, -1, 0, x0 + w, y0],
    180 => [-1, 0, 0, -1, x0 + w, y0 + h],
    270 => [0, -1, 1, 0, x0, y0 + h],
    _ => [1, 0, 0, 1, x0, y0],
  };
  return [sx * rot[0], sx * rot[1], sy * rot[2], sy * rot[3], rot[4], rot[5]];
}
