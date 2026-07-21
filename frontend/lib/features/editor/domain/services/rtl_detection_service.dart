/// Service for detecting text direction (RTL vs LTR) from content.
///
/// Used by the text renderer and the inline text editor to auto-set
/// [TextDirection] when the annotation doesn't have an explicit override.
/// This matches how professional editors handle mixed-direction documents.
class RtlDetectionService {
  const RtlDetectionService();

  /// Returns true if the first strong directional character in [text] is RTL.
  ///
  /// Covers: Arabic (0600–06FF), Hebrew (0590–05FF), Syriac (0700–074F),
  /// Arabic Supplement (0750–077F), Arabic Extended-A (08A0–08FF),
  /// Arabic Presentation Forms A/B (FB50–FDFF, FE70–FEFF).
  bool isRtl(String text) {
    for (final codeUnit in text.runes) {
      if (_isRtlCodePoint(codeUnit)) return true;
      if (_isLtrCodePoint(codeUnit)) return false;
    }
    return false; // default LTR if no strong character found
  }

  /// Returns true if the majority of strong characters in [text] are RTL.
  /// Useful for mixed-direction paragraphs (e.g. Arabic with English names).
  bool isMajorityRtl(String text) {
    int rtl = 0;
    int ltr = 0;
    for (final codeUnit in text.runes) {
      if (_isRtlCodePoint(codeUnit)) {
        rtl++;
      } else if (_isLtrCodePoint(codeUnit)) {
        ltr++;
      }
    }
    return rtl > ltr;
  }

  /// Suggest text alignment based on detected direction.
  /// RTL text → right-aligned; LTR → left-aligned.
  String suggestAlignment(String text) {
    return isRtl(text) ? 'right' : 'left';
  }

  bool _isRtlCodePoint(int cp) {
    return (cp >= 0x0590 && cp <= 0x05FF) || // Hebrew
        (cp >= 0x0600 && cp <= 0x06FF) || // Arabic
        (cp >= 0x0700 && cp <= 0x074F) || // Syriac
        (cp >= 0x0750 && cp <= 0x077F) || // Arabic Supplement
        (cp >= 0x08A0 && cp <= 0x08FF) || // Arabic Extended-A
        (cp >= 0xFB50 && cp <= 0xFDFF) || // Arabic Presentation Forms-A
        (cp >= 0xFE70 && cp <= 0xFEFF); // Arabic Presentation Forms-B
  }

  bool _isLtrCodePoint(int cp) {
    return (cp >= 0x0041 && cp <= 0x005A) || // A-Z
        (cp >= 0x0061 && cp <= 0x007A) || // a-z
        (cp >= 0x00C0 && cp <= 0x024F); // Latin Extended
  }
}
