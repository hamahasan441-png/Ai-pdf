import 'dart:convert';
import 'dart:typed_data';

import 'package:ai_pdf/features/editor/data/pdf_source/pdf_object_store.dart';

/// Kinds of field the editor can add to a PDF.
enum NewFieldKind { text, checkbox, choice, signature }

/// A form field to create, as the editor describes it.
class NewFormField {
  /// Requested name; made unique against the form when written.
  final String name;
  final NewFieldKind kind;

  /// Box on the displayed page, 0..1 from its top left: [left, top, right, bottom].
  final List<double> rect;

  /// Text value, or the selected option of a choice.
  final String value;
  final bool checked;
  final List<String> options;
  final bool required;
  final bool multiline;

  /// Font size in pt; 0 sizes the text to the box.
  final double fontSize;

  /// 0: left, 1: centre, 2: right.
  final int align;

  /// 0xRRGGBB, or null for none.
  final int? borderColor;
  final int? fillColor;

  const NewFormField({
    required this.name,
    required this.kind,
    required this.rect,
    this.value = '',
    this.checked = false,
    this.options = const [],
    this.required = false,
    this.multiline = false,
    this.fontSize = 0,
    this.align = 0,
    this.borderColor = 0x000000,
    this.fillColor,
  });
}

/// Helvetica advance widths (1/1000 em) for ASCII 32..126, from its AFM.
const List<int> _helvetica = [
  278, 278, 355, 556, 556, 889, 667, 191, 333, 333, 389, 584, 278, 333, 278, 278, //
  556, 556, 556, 556, 556, 556, 556, 556, 556, 556, 278, 278, 584, 584, 584, 556, //
  1015, 667, 667, 722, 722, 667, 611, 778, 722, 278, 500, 667, 556, 833, 722, 778, //
  667, 778, 722, 667, 611, 722, 667, 944, 667, 667, 611, 278, 278, 278, 469, 556, //
  333, 556, 556, 500, 556, 556, 278, 556, 556, 222, 222, 500, 222, 833, 556, 556, //
  556, 556, 333, 500, 278, 556, 500, 722, 500, 500, 500, 334, 260, 334, 584,
];

/// Width of [text] in Helvetica at [size] pt. Latin-1 letters outside ASCII
/// count as an average glyph.
double helveticaWidth(String text, double size) {
  var w = 0;
  for (final c in text.runes) {
    w += c >= 32 && c <= 126 ? _helvetica[c - 32] : 556;
  }
  return w * size / 1000;
}

/// Whether [text] can be drawn with the standard Helvetica font in
/// WinAnsiEncoding (printable ASCII and Latin-1).
bool winAnsiEncodable(String text) =>
    text.runes.every((c) => c == 0x0A || (c >= 0x20 && c <= 0x7E) || (c >= 0xA0 && c <= 0xFF));

String _n(double v) => PdfNum.of(v).raw;

String _rgb(int c) => '${_n(((c >> 16) & 0xFF) / 255)} ${_n(((c >> 8) & 0xFF) / 255)} ${_n((c & 0xFF) / 255)}';

/// Background and border of a [width] × [height] widget box.
String _frame(double width, double height, int? fill, int? border) {
  final b = StringBuffer();
  if (fill != null) b.write('q ${_rgb(fill)} rg 0 0 ${_n(width)} ${_n(height)} re f Q\n');
  if (border != null) {
    b.write('q ${_rgb(border)} RG 1 w 0.5 0.5 ${_n(width - 1)} ${_n(height - 1)} re S Q\n');
  }
  return b.toString();
}

/// Content of a text-field appearance stream (Helvetica as /Helv) showing
/// [text] in a [width] × [height] box. [fontSize] 0 fits the box. [quadding]
/// aligns it (0 left, 1 centre, 2 right). Returns null when the text cannot
/// be drawn with Helvetica; the viewer then draws the value itself
/// (/NeedAppearances).
Uint8List? textAppearance(
  String text,
  double width,
  double height,
  double fontSize, {
  bool multiline = false,
  int quadding = 0,
  int? fill,
  int? border,
}) {
  if (!winAnsiEncodable(text) || width <= 2 || height <= 2) return null;
  final lines = multiline ? text.split('\n') : [text.replaceAll('\n', ' ')];
  var size = fontSize > 0 ? fontSize : (multiline ? 10.0 : (height * 0.7).clamp(4.0, 12.0));
  // Shrink an auto-sized single line that would overflow the box.
  if (fontSize <= 0 && !multiline) {
    final w = helveticaWidth(lines.first, 1);
    if (w > 0) size = size.clamp(4.0, (width - 4) / w).toDouble();
  }
  String esc(String s) => s.replaceAll(r'\', r'\\').replaceAll('(', r'\(').replaceAll(')', r'\)');
  double xOf(String line) => switch (quadding) {
        1 => (width - helveticaWidth(line, size)) / 2,
        2 => width - 2 - helveticaWidth(line, size),
        _ => 2,
      };
  final b = StringBuffer(_frame(width, height, fill, border))
    ..write('/Tx BMC\nq\n1 1 ${_n(width - 2)} ${_n(height - 2)} re W n\nBT\n/Helv ${_n(size)} Tf\n0 g\n');
  if (multiline) {
    // Each line placed absolutely, so alignment works per line.
    var y = height - 2 - size;
    var prevX = 0.0, prevY = 0.0;
    for (final line in lines) {
      final x = xOf(line);
      b.write('${_n(x - prevX)} ${_n(y - prevY)} Td (${esc(line)}) Tj\n');
      prevX = x;
      prevY = y;
      y -= size * 1.15;
    }
  } else {
    final baseline = (height - size * 0.72) / 2;
    b.write('${_n(xOf(lines.first))} ${_n(baseline)} Td\n(${esc(lines.first)}) Tj\n');
  }
  b.write('ET\nQ\nEMC\n');
  return Uint8List.fromList(latin1.encode(b.toString()));
}

/// The "on" and "off" appearances of a check box: a ZapfDingbats check
/// (/ZaDb) in the frame, and the empty frame.
(Uint8List, Uint8List) checkboxAppearances(double width, double height, {int? fill, int? border}) {
  final frame = _frame(width, height, fill, border);
  final size = (height < width ? height : width) * 0.8;
  final x = (width - 0.76 * size) / 2; // ZapfDingbats "4" (a20) is 760/1000 wide
  final y = (height - size * 0.7) / 2;
  final on = '$frame q BT 0 g /ZaDb ${_n(size)} Tf ${_n(x)} ${_n(y)} Td (4) Tj ET Q\n';
  return (Uint8List.fromList(latin1.encode(on)), Uint8List.fromList(latin1.encode(frame)));
}

/// Field flags (/Ff) for [f].
int fieldFlags(NewFormField f) {
  var ff = 0;
  if (f.required) ff |= 1 << 1;
  if (f.kind == NewFieldKind.text && f.multiline) ff |= 1 << 12;
  if (f.kind == NewFieldKind.choice) ff |= 1 << 17; // a drop-down list
  return ff;
}

/// A name for [wanted] that is not one of [taken] (full field names, or
/// their first part), adding "_2", "_3"… when needed. Dots are not allowed
/// in a partial name and become underscores.
String uniqueFieldName(String wanted, Set<String> taken) {
  var base = wanted.trim().replaceAll('.', '_');
  if (base.isEmpty) base = 'Field';
  bool used(String n) => taken.contains(n) || taken.any((t) => t.startsWith('$n.'));
  if (!used(base)) return base;
  var i = 2;
  while (used('${base}_$i')) {
    i++;
  }
  return '${base}_$i';
}
