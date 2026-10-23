import 'dart:ui' show Color;

/// A colour's channels as 0..255 integers. Flutter 3.27 made the channels
/// doubles (Color.r/g/b/a) and deprecated the integer getters; PDF output,
/// saved annotations and hex strings still want 8-bit values.
extension ColorBits on Color {
  int get alpha8 => (a * 255).round() & 0xFF;
  int get red8 => (r * 255).round() & 0xFF;
  int get green8 => (g * 255).round() & 0xFF;
  int get blue8 => (b * 255).round() & 0xFF;
}
