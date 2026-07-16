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

  /// Field kind: 'text' (default), 'check' (tick a checkbox/radio), or
  /// 'signature' (a signature line — rendered in a script-like style).
  final String type;

  /// True when the AI was not confident about this value/placement, so the
  /// review UI can flag it for the user to double-check.
  final bool uncertain;

  const FilledField({
    required this.page,
    required this.x,
    required this.y,
    required this.text,
    this.field = '',
    this.anchor = '',
    this.type = 'text',
    this.uncertain = false,
  });

  bool get isCheck => type == 'check';
  bool get isSignature => type == 'signature';

  /// Copy with an overridden value (used after the user edits it in review).
  FilledField withText(String newText) => FilledField(
      page: page,
      x: x,
      y: y,
      text: newText,
      field: field,
      anchor: anchor,
      type: type,
      uncertain: uncertain);

  /// Copy with refined coordinates (used to snap onto an OCR label box).
  FilledField withXY(double nx, double ny) => FilledField(
      page: page,
      x: nx,
      y: ny,
      text: text,
      field: field,
      anchor: anchor,
      type: type,
      uncertain: uncertain);

  /// Parse from a loosely-typed JSON map returned by the AI. Tolerant of
  /// missing/oddly-typed fields so a single bad entry never crashes filling.
  static FilledField? tryParse(dynamic json) {
    if (json is! Map) return null;
    final type = _parseType(json['type']);
    var text = (json['text'] ?? json['value'] ?? '').toString().trim();
    // Checkboxes: normalize to a visible mark, and skip ones meant to stay off.
    if (type == 'check') {
      final t = text.toLowerCase();
      if (t == 'no' || t == 'false' || t == 'off' || t == 'unchecked' || t == 'none') {
        return null;
      }
      text = 'X';
    }
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
      page: page,
      x: x,
      y: y,
      text: text,
      field: label,
      anchor: anchor,
      type: type,
      uncertain: _parseUncertain(json),
    );
  }

  static String _parseType(dynamic v) {
    final t = (v ?? '').toString().toLowerCase().trim();
    if (t == 'check' || t == 'checkbox' || t == 'tick' || t == 'radio') return 'check';
    if (t == 'signature' || t == 'sign' || t == 'sig') return 'signature';
    return 'text';
  }

  static bool _parseUncertain(Map json) {
    if (json['uncertain'] == true) return true;
    final conf = json['confidence'];
    if (conf is num) return conf < 0.5;
    if (conf is String) {
      final c = conf.toLowerCase().trim();
      return c == 'low' || c == 'uncertain' || c == 'guess' || c == 'unsure';
    }
    return false;
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
