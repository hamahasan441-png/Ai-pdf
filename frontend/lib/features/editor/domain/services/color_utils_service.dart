import 'dart:math' as math;
import 'dart:ui' show Color;

/// Color helpers for the editor's pickers and accessibility checks (Phase 24).
///
/// Parsing/formatting hex, WCAG relative luminance + contrast ratio, and
/// perceptually simple lighten/darken — everything a color picker, an
/// "auto‑readable text" helper, and an accessibility badge need. Pure Dart
/// (`dart:math` + `dart:ui` `Color`) → fully unit‑testable.
class ColorUtilsService {
  const ColorUtilsService();

  static final RegExp _hexRe = RegExp(r'^[0-9a-fA-F]+$');

  /// Parse `#RGB`, `#RRGGBB`, or `#AARRGGBB` (the leading `#` is optional).
  /// Returns null on malformed input.
  Color? parseHex(String input) {
    var s = input.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (!_hexRe.hasMatch(s)) return null;

    switch (s.length) {
      case 3: // RGB -> RRGGBB
        final r = _dup(s[0]);
        final g = _dup(s[1]);
        final b = _dup(s[2]);
        return Color.fromARGB(0xFF, r, g, b);
      case 6:
        final v = int.parse(s, radix: 16);
        return Color(0xFF000000 | v);
      case 8:
        final v = int.parse(s, radix: 16);
        return Color(v);
      default:
        return null;
    }
  }

  /// Format a color as an uppercase hex string. `#RRGGBB` by default, or
  /// `#AARRGGBB` when [includeAlpha] is true.
  String toHex(Color color, {bool includeAlpha = false}) {
    final r = _hex2(color.red);
    final g = _hex2(color.green);
    final b = _hex2(color.blue);
    if (includeAlpha) {
      return '#${_hex2(color.alpha)}$r$g$b';
    }
    return '#$r$g$b';
  }

  /// WCAG relative luminance in 0..1.
  double relativeLuminance(Color c) {
    final r = _linearize(c.red / 255.0);
    final g = _linearize(c.green / 255.0);
    final b = _linearize(c.blue / 255.0);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  /// WCAG contrast ratio between two colors (1..21). Order‑independent.
  double contrastRatio(Color a, Color b) {
    final la = relativeLuminance(a);
    final lb = relativeLuminance(b);
    final hi = math.max(la, lb);
    final lo = math.min(la, lb);
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Whether [foreground] on [background] meets a contrast threshold
  /// (WCAG AA body text is 4.5:1 by default).
  bool isReadable(Color foreground, Color background, {double minRatio = 4.5}) {
    return contrastRatio(foreground, background) >= minRatio;
  }

  /// Black or white — whichever reads better on [background].
  Color bestTextColor(Color background) {
    const black = Color(0xFF000000);
    const white = Color(0xFFFFFFFF);
    return contrastRatio(black, background) >= contrastRatio(white, background)
        ? black
        : white;
  }

  /// Move each channel toward white by [amount] (0..1). Alpha is preserved.
  Color lighten(Color c, double amount) {
    final t = amount.clamp(0.0, 1.0);
    return Color.fromARGB(
      c.alpha,
      _mix(c.red, 255, t),
      _mix(c.green, 255, t),
      _mix(c.blue, 255, t),
    );
  }

  /// Move each channel toward black by [amount] (0..1). Alpha is preserved.
  Color darken(Color c, double amount) {
    final t = amount.clamp(0.0, 1.0);
    return Color.fromARGB(
      c.alpha,
      _mix(c.red, 0, t),
      _mix(c.green, 0, t),
      _mix(c.blue, 0, t),
    );
  }

  // --- internals -----------------------------------------------------------

  int _dup(String ch) => int.parse('$ch$ch', radix: 16);

  String _hex2(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();

  double _linearize(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  int _mix(int from, int to, double t) => (from + (to - from) * t).round();
}
