import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';

/// Kinds of interactive form field (PDF 32000-1 §12.7.4).
enum AcroFieldKind { text, checkbox, radio, choice, pushButton, signature }

/// One widget (the visible box) of a field.
class AcroWidget {
  /// Object number of the widget annotation. Equal to the field's when the
  /// field and its only widget are one dictionary.
  final int objNum;

  /// Index of the source page the widget is on.
  final int pageIndex;

  /// /Rect in the page's user space: [x0, y0, x1, y1], normalized so
  /// x0 < x1 and y0 < y1.
  final List<double> rect;

  /// Appearance state that means "on" for check boxes and radio buttons
  /// (without the leading slash), or null.
  final String? onState;

  const AcroWidget({required this.objNum, required this.pageIndex, required this.rect, this.onState});

  double get width => rect[2] - rect[0];
  double get height => rect[3] - rect[1];
}

/// A terminal form field with its inherited attributes resolved.
class AcroField {
  /// Fully qualified name: the /T of every ancestor joined with dots.
  final String name;
  final int objNum;
  final AcroFieldKind kind;
  final int flags;

  /// Text and single choice: the string. Check box and radio: the state
  /// name, "Off" when unset. Multiple choice: a List<String>.
  final Object value;

  /// Choice options as (export value, shown text).
  final List<(String, String)> options;
  final int? maxLen;

  /// From /DA; 0 means "auto size".
  final double fontSize;
  final List<AcroWidget> widgets;

  const AcroField({
    required this.name,
    required this.objNum,
    required this.kind,
    required this.flags,
    required this.value,
    this.options = const [],
    this.maxLen,
    this.fontSize = 0,
    required this.widgets,
  });

  bool get readOnly => flags & 1 != 0;
  bool get multiline => kind == AcroFieldKind.text && flags & (1 << 12) != 0;
  bool get password => kind == AcroFieldKind.text && flags & (1 << 13) != 0;
  bool get comb => kind == AcroFieldKind.text && flags & (1 << 24) != 0;
  bool get combo => kind == AcroFieldKind.choice && flags & (1 << 17) != 0;
  bool get editableCombo => combo && flags & (1 << 18) != 0;
  bool get multiSelect => kind == AcroFieldKind.choice && flags & (1 << 21) != 0;

  /// Whether the editor lets the user change it.
  bool get fillable =>
      !readOnly &&
      !password &&
      (kind == AcroFieldKind.text ||
          kind == AcroFieldKind.checkbox ||
          kind == AcroFieldKind.radio ||
          kind == AcroFieldKind.choice);

  /// The "on" state a check box takes when ticked.
  String get checkedState =>
      widgets.map((w) => w.onState).firstWhere((s) => s != null, orElse: () => null) ?? 'Yes';

  /// Shown text of a choice value, falling back to the value itself.
  String displayOf(String exportValue) {
    for (final (export, shown) in options) {
      if (export == exportValue) return shown;
    }
    return exportValue;
  }
}

/// Reads the interactive form of a PDF.
class AcroFormReader {
  const AcroFormReader();

  static const int maxFields = 5000;
  static const int maxDepth = 32;

  List<AcroField> read(PdfObjectStore s) {
    final acro = s.resolve(s.catalog['/AcroForm']);
    if (acro is! PdfDict) return const [];
    final roots = s.resolve(acro['/Fields']);
    if (roots is! PdfArray) return const [];

    // Which page each annotation is on: /P is optional and sometimes wrong,
    // the page's /Annots is what readers draw.
    final pageOf = <int, int>{};
    for (var i = 0; i < s.pages.length; i++) {
      final annots = s.resolve(s.pages[i].dict['/Annots']);
      if (annots is! PdfArray) continue;
      for (final a in annots.items) {
        if (a is PdfRef) pageOf.putIfAbsent(a.num, () => i);
      }
    }

    final out = <AcroField>[];
    final seen = <int>{};

    void walk(PdfValue? node, String prefix, Map<String, PdfValue> inherited, int depth) {
      if (node is! PdfRef || depth > maxDepth || out.length >= maxFields || !seen.add(node.num)) return;
      final dict = s.resolve(node);
      if (dict is! PdfDict) return;
      final t = s.resolve(dict['/T']);
      final partial = t is PdfString ? t.text : null;
      final name = partial == null ? prefix : (prefix.isEmpty ? partial : '$prefix.$partial');
      final inh = {
        ...inherited,
        for (final k in const ['/FT', '/Ff', '/V', '/DA', '/Opt', '/MaxLen'])
          if (dict[k] != null) k: dict[k]!,
      };

      // Kids with /T are fields; kids without are this field's widgets.
      final kids = s.resolve(dict['/Kids']);
      final widgetRefs = <PdfRef>[];
      if (kids is PdfArray) {
        for (final k in kids.items) {
          final kd = s.resolve(k);
          if (kd is! PdfDict) continue;
          if (kd['/T'] != null || (kd['/Kids'] != null && kd['/Subtype'] == null)) {
            walk(k, name, inh, depth + 1);
          } else if (k is PdfRef) {
            widgetRefs.add(k);
          }
        }
        if (widgetRefs.isEmpty) return; // a pure parent node
      } else {
        widgetRefs.add(node); // field and widget in one dictionary
      }

      final field = _field(s, node.num, name, inh, widgetRefs, pageOf);
      if (field != null) out.add(field);
    }

    for (final r in roots.items) {
      walk(r, '', const {}, 0);
    }
    return out;
  }

  AcroField? _field(
    PdfObjectStore s,
    int num,
    String name,
    Map<String, PdfValue> inh,
    List<PdfRef> widgetRefs,
    Map<int, int> pageOf,
  ) {
    final ft = (s.resolve(inh['/FT']) as PdfName?)?.name;
    final ff = s.resolve(inh['/Ff']) is PdfNum ? (s.resolve(inh['/Ff']) as PdfNum).toInt() : 0;
    final kind = switch (ft) {
      '/Tx' => AcroFieldKind.text,
      '/Ch' => AcroFieldKind.choice,
      '/Sig' => AcroFieldKind.signature,
      '/Btn' when ff & (1 << 16) != 0 => AcroFieldKind.pushButton,
      '/Btn' when ff & (1 << 15) != 0 => AcroFieldKind.radio,
      '/Btn' => AcroFieldKind.checkbox,
      _ => null,
    };
    if (kind == null) return null;

    final widgets = <AcroWidget>[];
    for (final ref in widgetRefs) {
      final w = s.resolve(ref);
      if (w is! PdfDict) continue;
      final page = pageOf[ref.num];
      final rect = _rect(s.resolve(w['/Rect']));
      if (page == null || rect == null) continue; // not on any page: never shown
      final button = kind == AcroFieldKind.checkbox || kind == AcroFieldKind.radio;
      widgets.add(AcroWidget(objNum: ref.num, pageIndex: page, rect: rect, onState: button ? _onState(s, w) : null));
    }
    if (widgets.isEmpty) return null;

    final v = s.resolve(inh['/V']);
    final Object value = switch (kind) {
      AcroFieldKind.checkbox || AcroFieldKind.radio => v is PdfName ? v.name.substring(1) : 'Off',
      AcroFieldKind.choice when ff & (1 << 21) != 0 => [
          if (v is PdfString) v.text,
          if (v is PdfArray)
            for (final i in v.items)
              if (s.resolve(i) case final PdfString str) str.text,
        ],
      _ => v is PdfString ? v.text : (v is PdfArray && v.items.isNotEmpty ? _str(s, v.items.first) : ''),
    };

    final options = <(String, String)>[];
    final opt = s.resolve(inh['/Opt']);
    if (opt is PdfArray) {
      for (final o in opt.items) {
        final ov = s.resolve(o);
        if (ov is PdfString) {
          options.add((ov.text, ov.text));
        } else if (ov is PdfArray && ov.items.length >= 2) {
          options.add((_str(s, ov.items[0]), _str(s, ov.items[1])));
        }
      }
    }
    final maxLen = s.resolve(inh['/MaxLen']);
    return AcroField(
      name: name,
      objNum: num,
      kind: kind,
      flags: ff,
      value: value,
      options: options,
      maxLen: maxLen is PdfNum ? maxLen.toInt() : null,
      fontSize: _daFontSize(s.resolve(inh['/DA'])),
      widgets: widgets,
    );
  }

  static String _str(PdfObjectStore s, PdfValue v) {
    final r = s.resolve(v);
    return r is PdfString ? r.text : '';
  }

  static List<double>? _rect(PdfValue? v) {
    if (v is! PdfArray || v.items.length != 4) return null;
    final n = [for (final i in v.items) i is PdfNum ? i.toDouble() : double.nan];
    if (n.any((x) => !x.isFinite)) return null;
    final r = [
      n[0] < n[2] ? n[0] : n[2],
      n[1] < n[3] ? n[1] : n[3],
      n[0] < n[2] ? n[2] : n[0],
      n[1] < n[3] ? n[3] : n[1],
    ];
    return r[2] - r[0] > 0 && r[3] - r[1] > 0 ? r : null;
  }

  /// The non-Off key of a button's appearance states. /N of a text widget
  /// is a stream, whose dictionary keys (/Type, /BBox) are not states.
  static String? _onState(PdfObjectStore s, PdfDict w) {
    final ap = s.resolve(w['/AP']);
    if (ap is! PdfDict) return null;
    for (final key in const ['/N', '/D']) {
      final ref = ap[key];
      if (ref is PdfRef && s.object(ref.num)?.stream != null) continue;
      final states = s.resolve(ref);
      if (states is! PdfDict) continue;
      for (final k in states.entries.keys) {
        if (k != '/Off') return k.substring(1);
      }
    }
    return null;
  }

  /// The size operand of `Tf` in a /DA string; 0 when absent or auto.
  static double _daFontSize(PdfValue? da) {
    if (da is! PdfString) return 0;
    final m = RegExp(r'([\d.]+)\s+Tf').firstMatch(latin1.decode(da.bytes, allowInvalid: true));
    return double.tryParse(m?.group(1) ?? '') ?? 0;
  }
}

/// Where [rect] (user space [x0, y0, x1, y1]) shows on a page with [crop]
/// and final /Rotate [rotate], as a 0..1 rectangle from the displayed top
/// left. The inverse of [overlayMatrix] for the unscaled case.
Rect displayRect(List<double> rect, List<double> crop, int rotate) {
  final w = crop[2] - crop[0];
  final h = crop[3] - crop[1];
  if (w <= 0 || h <= 0) return Rect.zero;
  final r = ((rotate % 360) + 360) % 360;
  (double, double) map(double x, double y) {
    final u = (x - crop[0]) / w;
    final v = (y - crop[1]) / h;
    return switch (r) {
      90 => (v, u),
      180 => (1 - u, v),
      270 => (1 - v, 1 - u),
      _ => (u, 1 - v),
    };
  }

  final a = map(rect[0], rect[1]);
  final b = map(rect[2], rect[3]);
  return Rect.fromLTRB(
    a.$1 < b.$1 ? a.$1 : b.$1,
    a.$2 < b.$2 ? a.$2 : b.$2,
    a.$1 < b.$1 ? b.$1 : a.$1,
    a.$2 < b.$2 ? b.$2 : a.$2,
  );
}

/// Whether [text] can be drawn with the standard Helvetica font in
/// WinAnsiEncoding (printable ASCII and Latin-1).
bool winAnsiEncodable(String text) =>
    text.runes.every((c) => c == 0x0A || (c >= 0x20 && c <= 0x7E) || (c >= 0xA0 && c <= 0xFF));

/// Content of a text-field appearance stream (Helvetica as /Helv) showing
/// [text] in a [width] × [height] box. [fontSize] 0 fits the box. Returns
/// null when the text cannot be drawn with Helvetica; the viewer then
/// draws the value itself (/NeedAppearances).
Uint8List? textAppearance(String text, double width, double height, double fontSize, {bool multiline = false}) {
  if (!winAnsiEncodable(text) || width <= 2 || height <= 2) return null;
  final lines = multiline ? text.split('\n') : [text.replaceAll('\n', ' ')];
  var size = fontSize > 0 ? fontSize : (multiline ? 10.0 : (height * 0.7).clamp(4.0, 12.0));
  // Shrink an auto-sized single line that would overflow the box (Helvetica
  // averages about half an em per character).
  if (fontSize <= 0 && !multiline) {
    final longest = lines.first.length;
    if (longest > 0) size = size.clamp(4.0, (width - 4) / (longest * 0.5)).toDouble();
  }
  String n(double v) => PdfNum.of(v).raw;
  String esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
  final b = StringBuffer('/Tx BMC\nq\n1 1 ${n(width - 2)} ${n(height - 2)} re W n\nBT\n/Helv ${n(size)} Tf\n0 g\n');
  if (multiline) {
    final lead = size * 1.15;
    b.write('${n(lead)} TL\n2 ${n(height - 2 - size)} Td\n');
    for (var i = 0; i < lines.length; i++) {
      b.write('${i == 0 ? '' : 'T* '}(${esc(lines[i])}) Tj\n');
    }
  } else {
    final baseline = (height - size * 0.72) / 2;
    b.write('2 ${n(baseline)} Td\n(${esc(lines.first)}) Tj\n');
  }
  b.write('ET\nQ\nEMC\n');
  return Uint8List.fromList(latin1.encode(b.toString()));
}

/// The form of one PDF, with each source page's crop box and /Rotate so
/// widgets can be placed on the displayed page.
class AcroFormSnapshot {
  final List<AcroField> fields;
  final List<(List<double>, int)> pageGeometry;

  const AcroFormSnapshot(this.fields, this.pageGeometry);

  static const empty = AcroFormSnapshot([], []);

  bool get isEmpty => fields.isEmpty;

  /// Reads [bytes]; meant for `Isolate.run`.
  static AcroFormSnapshot read(Uint8List bytes) {
    final s = PdfObjectStore.parse(bytes);
    return AcroFormSnapshot(
      const AcroFormReader().read(s),
      [for (final p in s.pages) (p.cropBox, p.rotate)],
    );
  }

  /// Where [w] shows on its page after [quarterTurns] extra clockwise turns.
  Rect rectOf(AcroWidget w, {int quarterTurns = 0}) {
    if (w.pageIndex >= pageGeometry.length) return Rect.zero;
    final (crop, rotate) = pageGeometry[w.pageIndex];
    return displayRect(w.rect, crop, rotate + 90 * quarterTurns);
  }
}

/// The current value of [f]: the edited one if any, else the file's.
Object fieldValue(AcroField f, Map<String, Object> edits) => edits[f.name] ?? f.value;

/// Short text the editor and image exports show for [f] holding [value].
String fieldDisplayText(AcroField f, Object value) => switch (f.kind) {
      AcroFieldKind.choice when value is List => [for (final v in value) f.displayOf('$v')].join(', '),
      AcroFieldKind.choice => f.displayOf('$value'),
      AcroFieldKind.text => '$value',
      _ => '',
    };
