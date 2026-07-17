import '../../../core/services/ocr_service.dart';
import '../models/filled_field.dart';
import 'form_ontology.dart';

/// Structured information extracted from the user's info document.
///
/// [byKey] holds values found next to a recognizable label (canonical key ->
/// value). [byKind] holds typed values found anywhere by pattern (emails,
/// dates, IBANs…), used as a fallback when a form field has a known kind but no
/// labeled value was found in the info doc.
class InfoStore {
  final Map<String, String> byKey;
  final Map<ValueKind, List<String>> byKind;
  const InfoStore(this.byKey, this.byKind);

  bool get isEmpty => byKey.isEmpty && byKind.isEmpty;
}

class _Candidate {
  final String value;
  final double score; // 0..1 confidence
  const _Candidate(this.value, this.score);
}

/// Fully on-device (no API) smart form filler.
///
/// Two-step model: the caller OCRs the blank FORM and the INFO document, then:
///   1. [extractInfo] turns the info OCR into a structured [InfoStore].
///   2. [fillForm] detects each form field via the [FormOntology], resolves the
///      best value from the info store / profile using a multi-signal score,
///      validates it against the field's [ValueKind], and returns positioned
///      [FilledField]s ready to drop onto the real form in the editor.
///
/// The scoring blends several independent signals (a "superposition" of
/// candidate sources that collapses to the highest-confidence valid value):
///   - labeled match in the info doc (strongest)
///   - a full-name synthesis for signature/name fields
///   - a typed loose value of the right kind found anywhere in the info doc
///   - the user's saved on-device profile (fallback)
/// with a validation bonus/penalty per field kind.
class SmartFormFiller {
  SmartFormFiller._();

  static final RegExp _emailRe =
      RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
  static final RegExp _ibanRe = RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{10,30}\b');
  static final RegExp _dateRe = RegExp(
      r'\b\d{1,2}[.\-/]\d{1,2}[.\-/]\d{2,4}\b|\b\d{4}-\d{2}-\d{2}\b');
  static final RegExp _phoneRe = RegExp(r'\+?\d[\d\s/()-]{6,}\d');
  static final RegExp _plzRe = RegExp(r'\b\d{5}\b');

  // ---- Step 1: extract structured info from the info document ------------

  static InfoStore extractInfo(List<OcrResult> pages) {
    final byKey = <String, String>{};
    final byKind = <ValueKind, List<String>>{};

    void addKind(ValueKind k, String v) {
      final t = v.trim();
      if (t.isEmpty) return;
      final list = byKind.putIfAbsent(k, () => <String>[]);
      if (!list.contains(t)) list.add(t);
    }

    for (final page in pages) {
      final lines = page.lines;
      for (var i = 0; i < lines.length; i++) {
        final raw = lines[i].text.trim();
        if (raw.isEmpty) continue;
        final colon = raw.indexOf(':');
        if (colon > 0 && colon < raw.length - 1) {
          // "Label: value" on one line.
          final label = raw.substring(0, colon).trim();
          final value = _clean(raw.substring(colon + 1));
          final key = FormOntology.match(label);
          if (key != null && value.isNotEmpty &&
              _valid(FormOntology.kindOf(key), value)) {
            byKey.putIfAbsent(key, () => value);
          }
        } else {
          // A label-only line: take the next line as its value (common on ID
          // cards / certificates where the value sits just below the label).
          final key = FormOntology.match(raw);
          if (key != null && !RegExp(r'\d').hasMatch(raw) && i + 1 < lines.length) {
            final nv = _clean(lines[i + 1].text);
            if (nv.isNotEmpty &&
                FormOntology.match(nv) == null &&
                _valid(FormOntology.kindOf(key), nv)) {
              byKey.putIfAbsent(key, () => nv);
            }
          }
        }
      }

      // Typed loose values found anywhere on the page (label-independent).
      final text = page.text;
      for (final m in _emailRe.allMatches(text)) {
        addKind(ValueKind.email, m.group(0)!);
      }
      for (final m in _ibanRe.allMatches(text)) {
        addKind(ValueKind.iban, m.group(0)!.replaceAll(' ', ''));
      }
      for (final m in _dateRe.allMatches(text)) {
        addKind(ValueKind.date, m.group(0)!);
      }
      for (final m in _phoneRe.allMatches(text)) {
        final v = m.group(0)!;
        if (v.replaceAll(RegExp(r'\D'), '').length >= 7) {
          addKind(ValueKind.phone, v);
        }
      }
      for (final m in _plzRe.allMatches(text)) {
        addKind(ValueKind.postalCode, m.group(0)!);
      }
    }

    // Cross-derive name parts so a form that splits Vorname/Nachname can be
    // filled from a single "Name", and vice versa. German forms almost always
    // split the name, while ID docs often print it as one line.
    final full = byKey['full_name'];
    if (full != null) {
      final parts =
          full.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
      if (parts.length >= 2) {
        byKey.putIfAbsent('first_name', () => parts.first);
        byKey.putIfAbsent('last_name', () => parts.sublist(1).join(' '));
      }
    } else {
      final f = byKey['first_name'];
      final l = byKey['last_name'];
      if (f != null && l != null) byKey['full_name'] = '$f $l';
    }

    return InfoStore(byKey, byKind);
  }

  // ---- Step 2: fill the form ---------------------------------------------

  static List<FilledField> fillForm(
    List<OcrResult> formPages,
    InfoStore info,
    Map<String, String> profile,
  ) {
    final out = <FilledField>[];

    // --- Pass 1: option / checkbox fields (Geschlecht, Familienstand) ---
    //
    // German forms usually offer these as tick-boxes rather than a blank. We
    // resolve the user's value to a canonical option and place a check 'X' on
    // the matching option word instead of writing text. [checkedCats] records
    // which groups we ticked so pass 2 doesn't also write text next to the
    // group's label.
    final genderVal =
        _canonicalOption('gender', info.byKey['gender'] ?? profile['gender'] ?? '');
    final maritalVal = _canonicalOption('marital',
        info.byKey['marital_status'] ?? profile['marital_status'] ?? '');
    final checkedCats = <String>{};
    if (genderVal != null || maritalVal != null) {
      for (var p = 0; p < formPages.length; p++) {
        for (final line in formPages[p].lines) {
          final t = line.text.trim();
          if (t.isEmpty || t.length > 24) continue;
          final opt = _identifyOption(t);
          if (opt == null) continue;
          final want = opt.$1 == 'gender' ? genderVal : maritalVal;
          if (want == null || want != opt.$2) continue;
          // Checkboxes usually sit just left of the option word.
          final x = (line.x - 0.022).clamp(0.0, 0.97).toDouble();
          final y = line.y.clamp(0.0, 0.97).toDouble();
          out.add(FilledField(
            page: p + 1,
            x: x,
            y: y,
            text: 'X',
            field: t,
            anchor: t,
            type: 'check',
            uncertain: true,
          ));
          checkedCats.add(opt.$1);
        }
      }
    }

    // --- Pass 2: normal labelled fields ---
    for (var p = 0; p < formPages.length; p++) {
      for (final line in formPages[p].lines) {
        final label = line.text.trim();
        if (label.isEmpty || label.length > 60) continue;
        if (!_looksLikeLabel(label)) continue; // skip instruction sentences
        final key = FormOntology.match(label);
        if (key == null) continue; // only fill fields we recognize (precision)
        final kind = FormOntology.kindOf(key);

        // If we already ticked this option group, don't also write text next to
        // the group's label (avoids a redundant/mislocated value).
        if (kind == ValueKind.gender && checkedCats.contains('gender')) continue;
        if (key == 'marital_status' && checkedCats.contains('marital')) continue;

        final best = _resolve(key, kind, info, profile);
        if (best == null) continue;

        final x = (line.x + line.w + 0.012).clamp(0.0, 0.97).toDouble();
        final y = line.y.clamp(0.0, 0.97).toDouble();
        out.add(FilledField(
          page: p + 1,
          x: x,
          y: y,
          text: best.value,
          field: label.replaceAll(':', '').trim(),
          anchor: label,
          type: kind == ValueKind.signature ? 'signature' : 'text',
          uncertain: best.score < 0.6,
        ));
      }
    }
    return _dedupe(out);
  }

  /// Resolve a raw gender/marital value to a canonical option token. Handles
  /// German + English words and single-letter abbreviations. Female is checked
  /// before male so "female" is never mistaken for "male" (substring).
  static String? _canonicalOption(String category, String raw) {
    final s = raw.toLowerCase().trim();
    if (s.isEmpty) return null;
    if (category == 'gender') {
      if (s.contains('weib') || s.contains('female') || s.contains('frau') ||
          s == 'w' || s == 'f') {
        return 'female';
      }
      if (s.contains('divers') || s == 'd') return 'diverse';
      // 'mannl' catches an OCR'd "mannlich" (umlaut lost); avoid bare 'mann'
      // so surnames/occupations like "Kaufmann" don't get mistaken for male.
      if (s.contains('männ') || s.contains('mannl') || s.contains('male') ||
          s.contains('herr') || s == 'm') {
        return 'male';
      }
    } else {
      if (s.contains('ledig') || s.contains('single')) return 'single';
      if (s.contains('verheir') || s.contains('married')) return 'married';
      if (s.contains('geschied') || s.contains('divorc')) return 'divorced';
      if (s.contains('verwitw') || s.contains('widow')) return 'widowed';
    }
    return null;
  }

  /// Identify whether a short form line is a gender/marital OPTION word, and if
  /// so return its (category, canonical value).
  static (String, String)? _identifyOption(String text) {
    final g = _canonicalOption('gender', text);
    if (g != null) return ('gender', g);
    final m = _canonicalOption('marital', text);
    if (m != null) return ('marital', m);
    return null;
  }

  // ---- Resolution / scoring ----------------------------------------------

  static _Candidate? _resolve(
    String? key,
    ValueKind kind,
    InfoStore info,
    Map<String, String> profile,
  ) {
    final candidates = <_Candidate>[];

    // 1) Labeled value in the info document — strongest signal.
    if (key != null && (info.byKey[key] ?? '').trim().isNotEmpty) {
      candidates.add(_Candidate(info.byKey[key]!.trim(), 0.95));
    }
    // 2) Signatures + full-name fields: synthesize the person's name.
    if (kind == ValueKind.signature || key == 'full_name') {
      final name = _fullName(info, profile);
      if (name != null) candidates.add(_Candidate(name, 0.8));
    }
    // 3) A typed loose value of the right kind found anywhere in the info doc.
    final loose = info.byKind[kind];
    if (loose != null && loose.isNotEmpty) {
      candidates.add(_Candidate(loose.first, 0.65));
    }
    // 4) The user's saved profile — last-resort fallback.
    if (key != null && (profile[key] ?? '').trim().isNotEmpty) {
      candidates.add(_Candidate(profile[key]!.trim(), 0.55));
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.score.compareTo(a.score));
    // Collapse to the highest-scoring candidate that passes validation.
    for (final c in candidates) {
      if (_valid(kind, c.value)) return c;
    }
    return null;
  }

  static String? _fullName(InfoStore info, Map<String, String> profile) {
    final fn = info.byKey['full_name'];
    if (fn != null && fn.trim().isNotEmpty) return fn.trim();
    final first =
        (info.byKey['first_name'] ?? profile['first_name'] ?? '').trim();
    final last =
        (info.byKey['last_name'] ?? profile['last_name'] ?? '').trim();
    final combined = '$first $last'.trim();
    return combined.isEmpty ? null : combined;
  }

  /// Lenient per-kind validation to reject gross mismatches.
  static bool _valid(ValueKind kind, String v) {
    final s = v.trim();
    if (s.isEmpty || s.length > 80) return false;
    switch (kind) {
      case ValueKind.email:
        return s.contains('@') && s.contains('.');
      case ValueKind.phone:
        return s.replaceAll(RegExp(r'\D'), '').length >= 7;
      case ValueKind.date:
        return RegExp(r'\d').hasMatch(s);
      case ValueKind.postalCode:
        return RegExp(r'\d{3,}').hasMatch(s);
      case ValueKind.iban:
        return RegExp(r'^[A-Za-z]{2}\d').hasMatch(s.replaceAll(' ', ''));
      case ValueKind.name:
        return RegExp(r'[A-Za-zÀ-ÿ]').hasMatch(s);
      default:
        return true;
    }
  }

  /// A short, field-like caption rather than an instruction sentence. Keeps
  /// precision high: we only treat concise captions (or anything ending in a
  /// colon) as fillable labels.
  static bool _looksLikeLabel(String label) {
    final t = label.trim();
    if (t.endsWith(':')) return true;
    final words = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    return words <= 4;
  }

  /// Strip label leftovers / trailing separators from an extracted value.
  static String _clean(String v) =>
      v.trim().replaceAll(RegExp(r'^[:\-–]+'), '').replaceAll(RegExp(r'[;,]+$'), '').trim();

  /// Keep one value per detected label position so we never stack two answers
  /// on the same line.
  static List<FilledField> _dedupe(List<FilledField> fields) {
    final seen = <String>{};
    final out = <FilledField>[];
    for (final f in fields) {
      final k = '${f.page}|${f.anchor.toLowerCase().trim()}';
      if (seen.add(k)) out.add(f);
    }
    return out;
  }
}
