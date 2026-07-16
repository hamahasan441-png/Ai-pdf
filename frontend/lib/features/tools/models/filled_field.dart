/// A value the AI wants to write onto a form, with its target location.
///
/// Coordinates are normalized (0..1) relative to the page: x from the left,
/// y from the top. [page] is 1-based (page 1 = first page).
class FilledField {
  final int page;
  final double x;
  final double y;
  final String text;

  /// Human-readable field label (e.g. "First name") for the review step.
  final String field;

  /// Optional OCR label text the AI wants this value placed next to. Used to
  /// snap x/y precisely onto the detected label line. Empty = use x/y as-is.
  final String anchor;

  const FilledField({
    required this.page,
    required this.x,
    required this.y,
    required this.text,
    this.field = '',
    this.anchor = '',
  });

  /// Copy with an overridden value (used after the user edits it in review).
  FilledField withText(String newText) => FilledField(
      page: page, x: x, y: y, text: newText, field: field, anchor: anchor);

  /// Copy with refined coordinates (used to snap onto an OCR label box).
  FilledField withXY(double nx, double ny) => FilledField(
      page: page, x: nx, y: ny, text: text, field: field, anchor: anchor);

  /// Parse from a loosely-typed JSON map returned by the AI. Tolerant of
  /// missing/oddly-typed fields so a single bad entry never crashes filling.
  static FilledField? tryParse(dynamic json) {
    if (json is! Map) return null;
    final text = (json['text'] ?? json['value'] ?? '').toString().trim();
    if (text.isEmpty) return null;
    final label = (json['field'] ?? json['label'] ?? json['name'] ?? '').toString().trim();
    final anchor = (json['anchor'] ?? json['near'] ?? '').toString().trim();
    int page = _toInt(json['page']) ?? 1;
    if (page < 1) page = 1;
    double x = _toDouble(json['x']) ?? 0.15;
    double y = _toDouble(json['y']) ?? 0.15;
    // Some models return 0..100 (percent) instead of 0..1.
    if (x > 1.0) x = x / 100.0;
    if (y > 1.0) y = y / 100.0;
    x = x.clamp(0.0, 0.97);
    y = y.clamp(0.0, 0.97);
    return FilledField(
        page: page, x: x, y: y, text: text, field: label, anchor: anchor);
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
