
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart' show TtfParser;
import 'package:pdf/widgets.dart' as pw;

import 'package:ai_pdf/features/editor/data/font_file_validator.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Script buckets that map to a bundled Unicode font.
enum EmbeddedScript { arabic, hebrew, other }

/// Lazily loads bundled Unicode TrueType fonts and picks the right one for a
/// piece of text so it can be exported as **searchable vector text**.
///
/// The TTF files live in `assets/fonts/` (see that folder's README). [pick]
/// returns a font only when
/// * the font's `cmap` contains every character of the text,
/// * `pdf` 3.11's Arabic shaper has forms for every Arabic-script letter in
///   it ([pdfShaperSupports]), and
/// * the text does not mix right-to-left and left-to-right letters.
/// Otherwise it returns null and the export paints the text with Flutter's
/// own shaper into the page image: it looks right but is not searchable.
class PdfUnicodeFonts {
  pw.Font? notoSans;
  pw.Font? arabic;
  pw.Font? arabicBold;
  pw.Font? vazir;
  pw.Font? vazirBold;
  pw.Font? hebrew;
  pw.Font? hebrewBold;
  bool _loaded = false;
  final Map<pw.Font, Set<int>> _coverage = {};

  /// Attempt to load all known Unicode fonts once. Never throws.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    notoSans = await _tryLoad('assets/fonts/NotoSans-Regular.ttf');
    arabic = await _tryLoad('assets/fonts/NotoSansArabic-Regular.ttf');
    arabicBold = await _tryLoad('assets/fonts/NotoSansArabic-Bold.ttf');
    vazir = await _tryLoad('assets/fonts/Vazirmatn-Regular.ttf');
    vazirBold = await _tryLoad('assets/fonts/Vazirmatn-Bold.ttf');
    hebrew = await _tryLoad('assets/fonts/NotoSansHebrew-Regular.ttf');
    hebrewBold = await _tryLoad('assets/fonts/NotoSansHebrew-Bold.ttf');
  }

  /// True if at least one RTL Unicode font is available for vector export.
  bool get hasRtl => arabic != null || vazir != null || hebrew != null;

  Future<pw.Font?> _tryLoad(String assetPath) async {
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      if (!validateTrueType(bytes).ok) return null;
      final cmap = TtfParser(data).charToGlyphIndexMap.keys.toSet();
      final font = pw.Font.ttf(data);
      _coverage[font] = cmap;
      return font;
    } catch (_) {
      // Missing, truncated, or not a TrueType font. Export stays raster.
      return null;
    }
  }

  /// The embedded Unicode font that can render [t] as correct vector text,
  /// or null (caller then rasterizes the text as a safe fallback).
  pw.Font? pick(TextAnnotation t) {
    final text = t.text;
    if (!pdfShaperSupports(text) || mixesDirections(text)) return null;
    for (final font in _candidates(t)) {
      if (font != null && covers(font, text)) return font;
    }
    return null;
  }

  Iterable<pw.Font?> _candidates(TextAnnotation t) sync* {
    final bold = t.bold;
    switch (t.fontFamily) {
      case 'NotoSansArabic':
        yield bold ? (arabicBold ?? arabic) : arabic;
      case 'Vazirmatn':
        yield bold ? (vazirBold ?? vazir) : vazir;
      case 'NotoSansHebrew':
        yield bold ? (hebrewBold ?? hebrew) : hebrew;
    }
    switch (scriptOf(t.text)) {
      case EmbeddedScript.arabic:
        yield bold ? (arabicBold ?? arabic) : arabic;
        yield bold ? (vazirBold ?? vazir) : vazir;
      case EmbeddedScript.hebrew:
        yield bold ? (hebrewBold ?? hebrew) : hebrew;
      case EmbeddedScript.other:
        // No bold Noto Sans is loaded for this path; a regular face for a
        // bold annotation would not match the preview.
        if (!bold) yield notoSans;
    }
  }

  /// True when [font] was loaded here and its `cmap` has every
  /// non-whitespace character in [text].
  bool covers(pw.Font font, String text) {
    final cmap = _coverage[font];
    if (cmap == null) return false;
    for (final cp in text.runes) {
      if (cp == 0x20 || cp == 0x0A || cp == 0x200C || cp == 0x200D) continue;
      if (!cmap.contains(cp)) return false;
    }
    return true;
  }

  /// Whether `pdf` 3.11's built-in Arabic shaper has contextual forms for
  /// every Arabic-script letter in [text].
  ///
  /// That shaper substitutes Unicode presentation forms; it does not run the
  /// font's GSUB table. Letters with no presentation form, including the
  /// Sorani letters ڕ ڵ ێ ە and ۊ, stay in their isolated form and break the
  /// joins of their neighbours. Text with such letters must not be exported
  /// through it.
  static bool pdfShaperSupports(String text) {
    for (final cp in text.runes) {
      if (!_isArabic(cp)) continue;
      if (cp >= 0xFB50) continue; // already a presentation form
      if (_pdfShapedLetters.contains(cp)) continue;
      if (_pdfDiacritics.contains(cp)) continue;
      if (!_isArabicJoiningLetter(cp)) continue; // digits, punctuation, signs
      return false;
    }
    return true;
  }

  /// Whether [text] holds both right-to-left and Latin/other left-to-right
  /// letters. `pdf` 3.11 lays such a line out without a full bidi pass, so it
  /// is painted instead.
  static bool mixesDirections(String text) {
    var rtl = false;
    var ltr = false;
    for (final cp in text.runes) {
      if (_isArabic(cp) || _isHebrew(cp)) {
        rtl = true;
      } else if (_isStrongLtr(cp)) {
        ltr = true;
      }
      if (rtl && ltr) return true;
    }
    return false;
  }

  static bool _isStrongLtr(int cp) =>
      (cp >= 0x41 && cp <= 0x5A) ||
      (cp >= 0x61 && cp <= 0x7A) ||
      (cp >= 0xC0 && cp <= 0x24F && cp != 0xD7 && cp != 0xF7) ||
      (cp >= 0x370 && cp <= 0x52F);

  /// Letters in U+0620–U+06FF and U+0750–U+077F that join. Digits
  /// (U+0660–U+0669, U+06F0–U+06F9), punctuation and Quranic signs do not
  /// need shaping.
  static bool _isArabicJoiningLetter(int cp) =>
      (cp >= 0x0620 && cp <= 0x064A) ||
      (cp >= 0x066E && cp <= 0x066F) ||
      (cp >= 0x0671 && cp <= 0x06D3) ||
      cp == 0x06D5 ||
      (cp >= 0x06EE && cp <= 0x06EF) ||
      (cp >= 0x06FA && cp <= 0x06FC) ||
      cp == 0x06FF ||
      (cp >= 0x0750 && cp <= 0x077F);

  /// Keys of `_arabicSubstitionA` in pdf 3.11.3 `lib/src/pdf/font/arabic.dart`.
  /// test/editor/pdf_unicode_fonts_test.dart checks this list against that
  /// shaper so a package upgrade cannot change it silently.
  static const Set<int> _pdfShapedLetters = {
    0x0621, 0x0622, 0x0623, 0x0624, 0x0625, 0x0626, 0x0627, 0x0628, 0x0629,
    0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F, 0x0630, 0x0631, 0x0632,
    0x0633, 0x0634, 0x0635, 0x0636, 0x0637, 0x0638, 0x0639, 0x063A, 0x0640,
    0x0641, 0x0642, 0x0643, 0x0644, 0x0645, 0x0646, 0x0647, 0x0648, 0x0649,
    0x064A, 0x0671, 0x0677, 0x0679, 0x067A, 0x067B, 0x067E, 0x067F, 0x0680,
    0x0683, 0x0684, 0x0686, 0x0687, 0x0688, 0x068C, 0x068D, 0x068E, 0x0691,
    0x0698, 0x06A4, 0x06A6, 0x06A9, 0x06AD, 0x06AF, 0x06B1, 0x06B3, 0x06BA,
    0x06BB, 0x06BE, 0x06C0, 0x06C1, 0x06C5, 0x06C6, 0x06C7, 0x06C8, 0x06C9,
    0x06CB, 0x06CC, 0x06D0, 0x06D2, 0x06D3,
  };

  static const Set<int> _pdfDiacritics = {
    0x064B, 0x064C, 0x064D, 0x064E, 0x064F, 0x0650, 0x0651, 0x0652, 0x0670,
  };

  /// Classify a string by its first strong-script character.
  static EmbeddedScript scriptOf(String text) {
    for (final cp in text.runes) {
      if (_isArabic(cp)) return EmbeddedScript.arabic;
      if (_isHebrew(cp)) return EmbeddedScript.hebrew;
    }
    return EmbeddedScript.other;
  }

  static bool _isArabic(int cp) =>
      (cp >= 0x0600 && cp <= 0x06FF) || // Arabic
      (cp >= 0x0750 && cp <= 0x077F) || // Arabic Supplement
      (cp >= 0x08A0 && cp <= 0x08FF) || // Arabic Extended-A
      (cp >= 0xFB50 && cp <= 0xFDFF) || // Presentation Forms-A
      (cp >= 0xFE70 && cp <= 0xFEFF); // Presentation Forms-B

  static bool _isHebrew(int cp) =>
      (cp >= 0x0590 && cp <= 0x05FF) || (cp >= 0xFB1D && cp <= 0xFB4F);
}
