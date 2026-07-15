/// A value the AI wants to write onto a form, with its target location.
///
/// Coordinates are normalized (0..1) relative to the page: x from the left,
/// y from the top. [page] is 1-based (page 1 = first page).
class FilledField {
  final int page;
  final double x;
  final double y;
  final String text;

  const FilledField({
    required this.page,
    required this.x,
    required this.y,
    required this.text,
  });

  /// Parse from a loosely-typed JSON map returned by the AI. Tolerant of
  /// missing/oddly-typed fields so a single bad entry never crashes filling.
  static FilledField? tryParse(dynamic json) {
    if (json is! Map) return null;
    final text = (json['text'] ?? json['value'] ?? '').toString().trim();
    if (text.isEmpty) return null;
    int page = _toInt(json['page']) ?? 1;
    if (page < 1) page = 1;
    double x = _toDouble(json['x']) ?? 0.15;
    double y = _toDouble(json['y']) ?? 0.15;
    // Some models return 0..100 (percent) instead of 0..1.
    if (x > 1.0) x = x / 100.0;
    if (y > 1.0) y = y / 100.0;
    x = x.clamp(0.0, 0.97);
    y = y.clamp(0.0, 0.97);
    return FilledField(page: page, x: x, y: y, text: text);
  }

  static int? _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static double? _toDouble(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }
}
