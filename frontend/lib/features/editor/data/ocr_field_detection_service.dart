import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/ocr_service.dart';
import '../domain/entities/detected_field.dart';

/// Offline OCR-driven field detection for the editor.
///
/// This service classifies label-like OCR lines (name/date/email/etc.) and also
/// detects small square/circle glyphs that correspond to checkbox/radio form
/// elements. It deliberately returns only structured field targets; the editor
/// screen still decides how to present them and which tool state to switch to.
class OcrFieldDetectionService {
  const OcrFieldDetectionService();

  Future<List<DetectedField>> detectFieldsFromPageBytes({
    required Uint8List bytes,
    required OcrService ocr,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/detect_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes);
    try {
      final result = await ocr.recognize(file.path);
      final detected = <DetectedField>[];
      for (final line in result.lines) {
        if (!isFieldLabel(line.text)) continue;
        detected.add(DetectedField(
          Rect.fromLTWH(line.x, line.y, line.w, line.h),
          line.text.trim(),
          inferType(line.text),
        ));
      }

      // Shape-based detection: small, roughly-square OCR boxes with very short
      // text (1-3 chars) that aren't already a label are likely checkbox/radio
      // form elements. Catches drawn squares/circles that OCR reads as a random
      // character rather than a known glyph.
      for (final line in result.lines) {
        final t = line.text.trim();
        if (t.isEmpty || t.length > 3) continue;
        if (isFieldLabel(t)) continue;
        final aspect = line.w > 0 ? (line.h / line.w) : 1.0;
        final isSmall = line.w < 0.06 && line.h < 0.04;
        if (!isSmall) continue;
        if (aspect >= 0.6 && aspect <= 1.6) {
          final type = (t == 'O' || t == 'o' || t == '0')
              ? FieldType.radio
              : FieldType.checkbox;
          detected.add(DetectedField(
            Rect.fromLTWH(line.x, line.y, line.w, line.h),
            t,
            type,
          ));
        }
      }
      return detected;
    } finally {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  bool isFieldLabel(String t) {
    final s = t.trim();
    if (s.isEmpty || s.length > 60) return false;
    if (s.endsWith(':')) return true;
    if (RegExp(r'_{2,}').hasMatch(s)) return true;
    if (isCheckboxGlyph(s)) return true;
    if (isRadioGlyph(s)) return true;
    return inferType(s) != FieldType.text;
  }

  /// Detect visual checkbox glyphs that OCR recognizes as characters.
  bool isCheckboxGlyph(String s) {
    final t = s.trim();
    if (t.length <= 3) {
      if (RegExp(r'^[\[\]()\u25A1\u2610\u2611\u2612\u25A0\u25FB\u25FC\u2B1C□☐☑☒■◻◼⬜]+$')
          .hasMatch(t)) {
        return true;
      }
      if (RegExp(r'^[xX]$').hasMatch(t)) return true;
    }
    return false;
  }

  /// Detect visual radio button glyphs (circles).
  bool isRadioGlyph(String s) {
    final t = s.trim();
    if (t.length <= 2) {
      if (RegExp(r'^[\u25CB\u25CE\u25C9\u25EF\u26AA\u26AB○◎◉◯⚪⚫]+$')
          .hasMatch(t)) {
        return true;
      }
      if (t == 'O' || t == 'o' || t == '()') return true;
    }
    return false;
  }

  FieldType inferType(String label) {
    final s = label.toLowerCase();
    bool has(List<String> ks) => ks.any((k) => s.contains(k));
    if (has(['signature', 'unterschrift', 'sign here', 'signed'])) {
      return FieldType.signature;
    }
    if (isCheckboxGlyph(label.trim())) return FieldType.checkbox;
    if (isRadioGlyph(label.trim())) return FieldType.radio;
    if (s.trim().length <= 12 &&
        has(['ja', 'nein', 'yes', 'no', 'männlich', 'weiblich', 'divers', 'ledig', 'verheiratet'])) {
      return FieldType.checkbox;
    }
    if (has(['e-mail', 'email', 'e mail'])) return FieldType.email;
    if (has(['date', 'datum', 'birth', 'geburt', 'geboren', 'dob', 'valid', 'expiry'])) {
      return FieldType.date;
    }
    if (has(['phone', 'tel', 'telefon', 'mobile', 'handy', 'fax'])) {
      return FieldType.phone;
    }
    if (has([
      'amount',
      'betrag',
      'iban',
      'zip',
      'postal',
      'plz',
      'number',
      'nummer',
      'no.',
      'nr',
      'sum',
      'total',
      'konto',
      'account',
      'salary',
      'income',
      'einkommen',
    ])) {
      return FieldType.number;
    }
    if (has(['name', 'vorname', 'nachname', 'first name', 'last name', 'surname', 'familienname'])) {
      return FieldType.name;
    }
    return FieldType.text;
  }
}
