import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';

export 'package:ai_pdf/features/editor/data/pdf_source/form_field_builder.dart' show textAppearance, winAnsiEncodable;

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

/// What a text field's own scripts (/AA) say its value is: the formats of
/// Acrobat's standard form functions (AFNumber_Format, AFDate_FormatEx,
/// AFSpecial_Format…).
enum AcroValueFormat { none, number, date, time, zip, phone }

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

  /// Text alignment (/Q): 0 left, 1 centre, 2 right.
  final int quadding;

  /// The name shown to people (/TU), when the form gives one.
  final String? alternateName;

  /// The value format the field's scripts enforce, and for dates their
  /// pattern ("dd.mm.yyyy").
  final AcroValueFormat format;
  final String? datePattern;
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
    this.quadding = 0,
    this.alternateName,
    this.format = AcroValueFormat.none,
    this.datePattern,
    required this.widgets,
  });

  bool get readOnly => flags & 1 != 0;

  /// The form asks for a value before it is submitted (/Ff bit 2).
  bool get required => flags & (1 << 1) != 0;
  bool get multiline => kind == AcroFieldKind.text && flags & (1 << 12) != 0;
  bool get password => kind == AcroFieldKind.text && flags & (1 << 13) != 0;
  bool get comb => kind == AcroFieldKind.text && flags & (1 << 24) != 0;
  bool get combo => kind == AcroFieldKind.choice && flags & (1 << 17) != 0;
  bool get editableCombo => combo && flags & (1 << 18) != 0;
  bool get multiSelect => kind == AcroFieldKind.choice && flags & (1 << 21) != 0;

  /// Whether the editor lets the user change it. A signature field is
  /// included so a tap can place a signature on it; a read-only one is not.
  bool get fillable =>
      !readOnly &&
      !password &&
      (kind == AcroFieldKind.text ||
          kind == AcroFieldKind.checkbox ||
          kind == AcroFieldKind.radio ||
          kind == AcroFieldKind.choice ||
          kind == AcroFieldKind.signature);

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

    // /Q may be set once for the whole form.
    final formDefaults = <String, PdfValue>{if (acro['/Q'] != null) '/Q': acro['/Q']!};

    void walk(PdfValue? node, String prefix, Map<String, PdfValue> inherited, int depth) {
      if (node is! PdfRef || depth > maxDepth || out.length >= maxFields || !seen.add(node.num)) return;
      final dict = s.resolve(node);
      if (dict is! PdfDict) return;
      final t = s.resolve(dict['/T']);
      final partial = t is PdfString ? t.text : null;
      final name = partial == null ? prefix : (prefix.isEmpty ? partial : '$prefix.$partial');
      final inh = {
        ...inherited,
        for (final k in const ['/FT', '/Ff', '/V', '/DA', '/Opt', '/MaxLen', '/Q', '/TU', '/AA'])
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
      walk(r, '', formDefaults, 0);
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
    final q = s.resolve(inh['/Q']);
    final tu = s.resolve(inh['/TU']);
    final (format, datePattern) = kind == AcroFieldKind.text ? _format(s, inh['/AA']) : (AcroValueFormat.none, null);
    return AcroField(
      name: name,
      objNum: num,
      kind: kind,
      flags: ff,
      value: value,
      options: options,
      maxLen: maxLen is PdfNum ? maxLen.toInt() : null,
      fontSize: _daFontSize(s.resolve(inh['/DA'])),
      quadding: q is PdfNum && q.toInt() >= 0 && q.toInt() <= 2 ? q.toInt() : 0,
      alternateName: tu is PdfString && tu.text.trim().isNotEmpty ? tu.text.trim() : null,
      format: format,
      datePattern: datePattern,
      widgets: widgets,
    );
  }

  /// The format the field's format (/F) or keystroke (/K) script sets.
  static (AcroValueFormat, String?) _format(PdfObjectStore s, PdfValue? aa) {
    final actions = s.resolve(aa);
    if (actions is! PdfDict) return (AcroValueFormat.none, null);
    final js = StringBuffer();
    for (final key in const ['/F', '/K']) {
      final action = s.resolve(actions[key]);
      if (action is! PdfDict) continue;
      final code = action['/JS'];
      final value = s.resolve(code);
      if (value is PdfString) {
        js.writeln(latin1.decode(value.bytes, allowInvalid: true));
      } else if (code is PdfRef) {
        final obj = s.object(code.num);
        if (obj?.stream != null) {
          try {
            js.writeln(latin1.decode(s.decodeStream(obj!), allowInvalid: true));
          } on PdfSourceException {
            // A script we cannot decode tells us nothing.
          }
        }
      }
    }
    return parseFieldFormat(js.toString());
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

/// Whether [value] counts as not filled in.
bool fieldValueEmpty(Object value) => switch (value) {
      String v => v.isEmpty || v == 'Off',
      List v => v.isEmpty,
      _ => false,
    };

/// Required fields the user can fill that are still empty, among those on
/// [sourcePages] (the source pages the export keeps), in form order.
List<AcroField> emptyRequiredFields(AcroFormSnapshot form, Map<String, Object> edits, Iterable<int> sourcePages) {
  final kept = sourcePages.toSet();
  return [
    for (final f in form.fields)
      if (f.required && f.fillable && f.widgets.any((w) => kept.contains(w.pageIndex)) && fieldValueEmpty(fieldValue(f, edits)))
        f,
  ];
}

/// Fields in the order a reader fills them: by page as the editor shows
/// them ([slotOf] maps a source page to its position, -1 when not shown),
/// then top to bottom and left to right on the displayed page. Text and
/// choice fields only, unless [includeButtons] (check boxes and radios).
List<(AcroField, AcroWidget, int)> fillOrder(
  AcroFormSnapshot form,
  int Function(int sourcePage) slotOf, {
  int Function(int slot)? quarterTurnsOf,
  bool includeButtons = false,
}) {
  final out = <(AcroField, AcroWidget, int, Rect)>[];
  for (final f in form.fields) {
    final typed = f.kind == AcroFieldKind.text || f.kind == AcroFieldKind.choice;
    final button = f.kind == AcroFieldKind.checkbox || f.kind == AcroFieldKind.radio;
    if (!f.fillable || !(typed || (includeButtons && button))) continue;
    for (final w in f.widgets) {
      final slot = slotOf(w.pageIndex);
      if (slot < 0) continue;
      out.add((f, w, slot, form.rectOf(w, quarterTurns: quarterTurnsOf?.call(slot) ?? 0)));
    }
  }
  out.sort((a, b) {
    if (a.$3 != b.$3) return a.$3.compareTo(b.$3);
    // Same row when the tops are within half the smaller height.
    final tol = (a.$4.height < b.$4.height ? a.$4.height : b.$4.height) / 2;
    if ((a.$4.top - b.$4.top).abs() > tol) return a.$4.top.compareTo(b.$4.top);
    return a.$4.left.compareTo(b.$4.left);
  });
  return [for (final e in out) (e.$1, e.$2, e.$3)];
}

/// The value format named by a field's JavaScript, for the calls Acrobat's
/// own forms use. Anything else is [AcroValueFormat.none].
(AcroValueFormat, String?) parseFieldFormat(String js) {
  final date = RegExp(r'''AFDate_(?:Format|Keystroke)Ex\s*\(\s*["']([^"']+)["']''').firstMatch(js);
  if (date != null) return (AcroValueFormat.date, date.group(1));
  final dateIndex = RegExp(r'AFDate_(?:Format|Keystroke)\s*\(\s*(\d+)').firstMatch(js);
  if (dateIndex != null) {
    // Acrobat's numbered date formats (AFDate_Format(n)).
    const patterns = [
      'm/d', 'm/d/yy', 'mm/dd/yy', 'mm/yy', 'd-mmm', 'd-mmm-yy', 'dd-mmm-yy', 'yy-mm-dd', //
      'mmm-yy', 'mmmm-yy', 'mmm d, yyyy', 'mmmm d, yyyy', 'm/d/yy h:MM tt', 'm/d/yy HH:MM',
    ];
    final i = int.parse(dateIndex.group(1)!);
    return (AcroValueFormat.date, i < patterns.length ? patterns[i] : null);
  }
  if (RegExp(r'AFTime_(?:Format|Keystroke)').hasMatch(js)) return (AcroValueFormat.time, null);
  final special = RegExp(r'AFSpecial_(?:Format|Keystroke)\s*\(\s*(\d+)').firstMatch(js);
  if (special != null) {
    return switch (special.group(1)) {
      '0' || '1' => (AcroValueFormat.zip, null),
      '2' => (AcroValueFormat.phone, null),
      _ => (AcroValueFormat.number, null),
    };
  }
  if (RegExp(r'AF(?:Number|Percent)_(?:Format|Keystroke)').hasMatch(js)) return (AcroValueFormat.number, null);
  return (AcroValueFormat.none, null);
}

