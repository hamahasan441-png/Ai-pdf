import 'package:flutter/services.dart';

import 'package:ai_pdf/features/editor/data/pdf_source/acro_form.dart';
import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// What a text field asks for, which decides the keyboard, the input mask
/// and whether a date picker is offered.
enum FieldInput { text, multiline, number, date, time, phone, email, zip }

/// What the editor knows about a field it is about to fill.
class FieldSmarts {
  final FieldInput input;

  /// For [FieldInput.date]: an intl pattern such as "dd.MM.yyyy".
  final String? datePattern;

  /// What the field is called for people: the label printed next to it on
  /// the page, else its /TU, else its name.
  final String label;

  const FieldSmarts(this.input, this.label, {this.datePattern});

  TextInputType get keyboard => switch (input) {
        FieldInput.number || FieldInput.zip => const TextInputType.numberWithOptions(decimal: true),
        FieldInput.date || FieldInput.time => TextInputType.datetime,
        FieldInput.phone => TextInputType.phone,
        FieldInput.email => TextInputType.emailAddress,
        FieldInput.multiline => TextInputType.multiline,
        FieldInput.text => TextInputType.text,
      };
}

/// Works out [FieldSmarts] for form fields: from the field's own format
/// scripts first, then from the words of its label and name.
class FormFillSmarts {
  const FormFillSmarts();

  static const _date = [
    'datum', 'date', 'geburtsdatum', 'geboren', 'birth', 'tt.mm', 'dd.mm', 'dd/mm', 'mm/dd', 'jjjj', 'yyyy', //
    'بەروار', 'تاريخ', 'تاریخ', 'fecha',
  ];
  static const _email = ['e-mail', 'email', 'mail', 'ئیمەیڵ', 'البريد', 'ایمیل', 'correo'];
  static const _phone = ['telefon', 'phone', 'tel.', 'mobil', 'handy', 'fax', 'تەلەفۆن', 'مۆبایل', 'هاتف', 'تلفن', 'teléfono'];
  static const _zip = ['plz', 'postleitzahl', 'zip', 'postal', 'postcode', 'código postal'];
  static const _number = ['hausnummer', 'hausnr', 'betrag', 'amount', 'anzahl', 'summe', 'menge', 'quantity', 'ژمارە', 'رقم', 'عدد'];

  FieldSmarts of(AcroField field, {Rect? rect, List<PdfTextElement> words = const []}) {
    final label = (rect == null ? null : labelNear(rect, words)) ?? field.alternateName ?? _readable(field.name);
    switch (field.format) {
      case AcroValueFormat.date:
        return FieldSmarts(FieldInput.date, label, datePattern: intlDatePattern(field.datePattern) ?? _patternIn(label));
      case AcroValueFormat.time:
        return FieldSmarts(FieldInput.time, label);
      case AcroValueFormat.number:
        return FieldSmarts(FieldInput.number, label);
      case AcroValueFormat.zip:
        return FieldSmarts(FieldInput.zip, label);
      case AcroValueFormat.phone:
        return FieldSmarts(FieldInput.phone, label);
      case AcroValueFormat.none:
        break;
    }
    if (field.multiline) return FieldSmarts(FieldInput.multiline, label);
    final words0 = '$label ${field.alternateName ?? ''} ${field.name}'.toLowerCase();
    bool any(List<String> keys) => keys.any(words0.contains);
    if (any(_email)) return FieldSmarts(FieldInput.email, label);
    if (any(_date)) return FieldSmarts(FieldInput.date, label, datePattern: _patternIn(label) ?? 'dd.MM.yyyy');
    if (any(_phone)) return FieldSmarts(FieldInput.phone, label);
    if (any(_zip)) return FieldSmarts(FieldInput.zip, label);
    if (any(_number)) return FieldSmarts(FieldInput.number, label);
    return FieldSmarts(FieldInput.text, label);
  }

  /// The printed label of a field at [rect]: the nearest line of words just
  /// above it that starts over it, else the words just to its left on the
  /// same line. Rects are 0..1 on the shown page.
  String? labelNear(Rect rect, List<PdfTextElement> words) {
    final h = rect.height <= 0 ? 0.02 : rect.height;
    // Above: bottom within about one field height over the field's top, and
    // horizontally inside the field's span.
    final above = [
      for (final w in words)
        if (w.rect.bottom <= rect.top + h * 0.2 &&
            w.rect.bottom >= rect.top - h * 1.6 &&
            w.rect.left >= rect.left - h * 0.5 &&
            w.rect.left < rect.right)
          w,
    ];
    if (above.isNotEmpty) {
      final nearest = above.map((w) => w.rect.bottom).reduce((a, b) => a > b ? a : b);
      final line = above.where((w) => (w.rect.bottom - nearest).abs() < h * 0.5).toList()
        ..sort((a, b) => a.rect.left.compareTo(b.rect.left));
      final text = _clean(line.map((w) => w.text).join(' '));
      if (text.isNotEmpty) return text;
    }
    // Left: on the same line, ending shortly before the field.
    final left = [
      for (final w in words)
        if ((w.rect.center.dy - rect.center.dy).abs() < h * 0.6 && w.rect.right <= rect.left + 0.002 && w.rect.right > rect.left - 0.35)
          w,
    ]..sort((a, b) => a.rect.left.compareTo(b.rect.left));
    final text = _clean(left.map((w) => w.text).join(' '));
    return text.isEmpty ? null : text;
  }

  /// "3 Geburtsdatum (TT.MM.JJJJ)" → "Geburtsdatum (TT.MM.JJJJ)": a leading
  /// question number is not part of the label.
  static String _clean(String s) => s.replaceFirst(RegExp(r'^\d{1,3}[.)]?\s+'), '').trim();

  /// "txtVorname_1" → "Vorname 1".
  static String _readable(String name) {
    final last = name.split('.').last;
    return last.replaceAll(RegExp(r'[_\-]+'), ' ').replaceFirst(RegExp(r'^(txt|tf|fld|field)\s*', caseSensitive: false), '').trim();
  }

  /// The date pattern a label spells out: "TT.MM.JJJJ" (German),
  /// "DD/MM/YYYY", "MM/DD/YYYY", "YYYY-MM-DD".
  static String? _patternIn(String label) {
    final m = RegExp(r'\b([TtDdMmJjYy]{1,4})([./\-])([TtDdMmJjYy]{1,4})\2([TtDdMmJjYy]{2,4})\b').firstMatch(label);
    if (m == null) return null;
    String part(String p) {
      final c = p[0].toLowerCase();
      return switch (c) {
        't' || 'd' => 'd' * p.length,
        'm' => 'M' * p.length,
        _ => 'y' * p.length,
      };
    }

    return '${part(m.group(1)!)}${m.group(2)}${part(m.group(3)!)}${m.group(2)}${part(m.group(4)!)}';
  }
}

/// An Acrobat date pattern ("dd.mm.yyyy": m is month, M is minute) as an
/// intl pattern ("dd.MM.yyyy").
String? intlDatePattern(String? acrobat) {
  if (acrobat == null || acrobat.trim().isEmpty) return null;
  final b = StringBuffer();
  for (final c in acrobat.split('')) {
    b.write(switch (c) {
      'm' => 'M',
      'M' => 'm',
      't' => 'a',
      _ => c,
    });
  }
  return b.toString().replaceAll('aa', 'a');
}

/// Types the separators of a numeric date pattern ("dd.MM.yyyy") for the
/// user: "1203" becomes "12.03", and only digits are kept. Patterns with
/// month names are left alone.
class DateMaskFormatter extends TextInputFormatter {
  final String pattern;

  DateMaskFormatter(this.pattern);

  bool get usable => RegExp(r'^[dMy]+([./\- ][dMy]+)*$').hasMatch(pattern) && !pattern.contains('MMM');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    if (!usable) return newValue;
    // Deleting a separator deletes it; do not put it straight back.
    if (newValue.text.length < oldValue.text.length) return newValue;
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final out = StringBuffer();
    var d = 0;
    for (var i = 0; i < pattern.length && d < digits.length; i++) {
      final c = pattern[i];
      if (c == 'd' || c == 'M' || c == 'y') {
        out.write(digits[d++]);
      } else {
        out.write(c);
      }
    }
    // A completed part is followed by its separator at once.
    final at = out.length;
    if (at < pattern.length && d == digits.length) {
      final next = pattern[at];
      if (next != 'd' && next != 'M' && next != 'y' && digits.isNotEmpty) out.write(next);
    }
    final text = out.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
