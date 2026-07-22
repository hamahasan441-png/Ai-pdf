/// Text case and typography transforms for the editor's text tools (Phase 25).
///
/// The operations behind a "change case / clean up" menu on a text selection:
/// upper / lower / title / sentence / toggle case, whitespace normalisation,
/// and straight‑to‑curly smart quotes. Pure string logic, no Flutter
/// dependency → fully unit‑testable.
class TextTransformService {
  const TextTransformService();

  String upper(String s) => s.toUpperCase();

  String lower(String s) => s.toLowerCase();

  /// Capitalise the first character of every whitespace‑separated word and
  /// lower‑case the rest. Whitespace is preserved exactly.
  String titleCase(String s) {
    return s.replaceAllMapped(RegExp(r'\S+'), (m) {
      final w = m.group(0)!;
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1).toLowerCase();
    });
  }

  /// Lower‑case everything, then capitalise the first letter of each sentence
  /// (sentences end at `.`, `!`, or `?`).
  String sentenceCase(String s) {
    final lower = s.toLowerCase();
    final buf = StringBuffer();
    var capitalizeNext = true;
    for (final rune in lower.runes) {
      var ch = String.fromCharCode(rune);
      if (capitalizeNext && _isLetter(rune)) {
        ch = ch.toUpperCase();
        capitalizeNext = false;
      }
      if (rune == 0x2E || rune == 0x21 || rune == 0x3F) {
        capitalizeNext = true; // . ! ?
      }
      buf.write(ch);
    }
    return buf.toString();
  }

  /// Swap the case of every letter.
  String toggleCase(String s) {
    final buf = StringBuffer();
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      final up = ch.toUpperCase();
      final low = ch.toLowerCase();
      if (ch == up && ch != low) {
        buf.write(low); // was upper
      } else if (ch == low && ch != up) {
        buf.write(up); // was lower
      } else {
        buf.write(ch); // no case
      }
    }
    return buf.toString();
  }

  /// Trim, and collapse every run of whitespace to a single space.
  String normalizeWhitespace(String s) =>
      s.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Convert straight quotes to typographic (curly) quotes.
  ///
  /// A double quote opens (`\u201C`) at the start or after whitespace/opening
  /// punctuation, otherwise closes (`\u201D`). A single quote after an
  /// alphanumeric becomes an apostrophe/closing (`\u2019`), otherwise an
  /// opening (`\u2018`).
  String smartQuotes(String s) {
    const ldq = '\u201C'; // “
    const rdq = '\u201D'; // ”
    const lsq = '\u2018'; // ‘
    const rsq = '\u2019'; // ’

    final buf = StringBuffer();
    int? prev;
    for (final rune in s.runes) {
      if (rune == 0x22) {
        buf.write(_opensQuote(prev) ? ldq : rdq);
      } else if (rune == 0x27) {
        buf.write(_isAlnum(prev) ? rsq : (_opensQuote(prev) ? lsq : rsq));
      } else {
        buf.write(String.fromCharCode(rune));
      }
      prev = rune;
    }
    return buf.toString();
  }

  // --- internals -----------------------------------------------------------

  bool _isLetter(int r) =>
      (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A) || r > 0x7F;

  bool _isAlnum(int? r) {
    if (r == null) return false;
    return _isLetter(r) || (r >= 0x30 && r <= 0x39);
  }

  /// Whether a quote at this position should open: start of string, or after
  /// whitespace or an opening bracket/quote.
  bool _opensQuote(int? prev) {
    if (prev == null) return true;
    if (prev == 0x20 || prev == 0x09 || prev == 0x0A || prev == 0x0D) {
      return true; // whitespace
    }
    // ( [ { “ ‘
    return prev == 0x28 ||
        prev == 0x5B ||
        prev == 0x7B ||
        prev == 0x201C ||
        prev == 0x2018;
  }
}
