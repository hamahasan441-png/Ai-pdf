import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Script buckets that map to a bundled Unicode font.
enum EmbeddedScript { arabic, hebrew, other }

/// Lazily loads bundled Unicode TrueType fonts and picks the right one for a
/// piece of text so RTL scripts can be exported as **searchable vector text**.
///
/// The TTF files live in `assets/fonts/` (see that folder's README). They are
/// declared as a whole-directory asset, so this loader can find them by name
/// once they are present. When a font is missing, [pick] returns null and the
/// export falls back to rasterizing the text — i.e. this is entirely optional
/// and safe to ship before the fonts are added.
class PdfUnicodeFonts {
  pw.Font? notoSans;
  pw.Font? arabic;
  pw.Font? arabicBold;
  pw.Font? vazir;
  pw.Font? vazirBold;
  pw.Font? hebrew;
  pw.Font? hebrewBold;
  bool _loaded = false;

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
      return pw.Font.ttf(data);
    } catch (_) {
      // Asset not bundled / not found — feature stays dormant, no crash.
      return null;
    }
  }

  /// The embedded Unicode font that can render [t], or null if none is loaded
  /// for its script (caller then rasterizes the text as a safe fallback).
  pw.Font? pick(TextAnnotation t) {
    final bold = t.bold;
    switch (t.fontFamily) {
      case 'NotoSansArabic':
        return bold ? (arabicBold ?? arabic) : arabic;
      case 'Vazirmatn':
        return bold ? (vazirBold ?? vazir) : vazir;
      case 'NotoSansHebrew':
        return bold ? (hebrewBold ?? hebrew) : hebrew;
    }
    switch (scriptOf(t.text)) {
      case EmbeddedScript.arabic:
        final regular = arabic ?? vazir;
        final heavy = arabicBold ?? vazirBold ?? regular;
        return bold ? heavy : regular;
      case EmbeddedScript.hebrew:
        return bold ? (hebrewBold ?? hebrew) : hebrew;
      case EmbeddedScript.other:
        return null;
    }
  }

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
