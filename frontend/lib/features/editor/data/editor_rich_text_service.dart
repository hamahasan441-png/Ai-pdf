import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// Service for applying per-selection rich-text styling to a [TextAnnotation].
///
/// When the user selects a range of text in the inline editor and taps a style
/// button (bold, italic, underline, colour), this service:
/// 1. Splits the existing runs at the selection boundaries.
/// 2. Applies the style override to the selected run(s).
/// 3. Merges adjacent runs with identical styling to keep the model compact.
///
/// The result is a new `runs` list that the annotation's `text` field indexes
/// into. If the result is a single run covering the whole text with no
/// overrides, the annotation is downgraded back to `runs = null` (plain mode).
class EditorRichTextService {
  const EditorRichTextService();

  /// Apply [style] to the character range [start]..[end] within [annotation].
  /// Returns the updated runs list (caller assigns to `annotation.runs`).
  List<TextRun>? applyStyle(
    TextAnnotation annotation, {
    required int start,
    required int end,
    bool? bold,
    bool? italic,
    bool? underline,
    Color? color,
    String? fontFamily,
    double? sizeScale,
  }) {
    final range = _range(annotation.text, start, end);
    if (range == null) return annotation.runs;
    final from = range.$1;
    final to = range.$2;

    // Expand the annotation into per-character runs (materialise if runs==null).
    final chars = _expand(annotation);
    
    // Apply the style override to the selected range.
    for (var i = from; i < to; i++) {
      chars[i] = _CharStyle(
        bold: bold ?? chars[i].bold,
        italic: italic ?? chars[i].italic,
        underline: underline ?? chars[i].underline,
        color: color ?? chars[i].color,
        fontFamily: fontFamily ?? chars[i].fontFamily,
        sizeScale: sizeScale ?? chars[i].sizeScale,
      );
    }

    // Collapse back into runs by merging consecutive identical styles.
    return _collapse(annotation.text, chars);
  }

  /// Toggle [bold] for the selection range (if all chars are bold → clear bold,
  /// otherwise → set bold). Same pattern for italic/underline.
  List<TextRun>? toggleBold(TextAnnotation a, int start, int end) {
    final range = _range(a.text, start, end);
    if (range == null) return a.runs;
    final chars = _expand(a);
    final allOn = chars.sublist(range.$1, range.$2).every((c) => (c.bold ?? a.bold) == true);
    for (var i = range.$1; i < range.$2; i++) {
      chars[i] = _CharStyle(
        bold: _toggled(allOn, a.bold),
        italic: chars[i].italic,
        underline: chars[i].underline,
        color: chars[i].color,
        fontFamily: chars[i].fontFamily,
        sizeScale: chars[i].sizeScale,
      );
    }
    return _collapse(a.text, chars);
  }

  List<TextRun>? toggleItalic(TextAnnotation a, int start, int end) {
    final range = _range(a.text, start, end);
    if (range == null) return a.runs;
    final chars = _expand(a);
    final allOn = chars.sublist(range.$1, range.$2).every((c) => (c.italic ?? a.italic) == true);
    for (var i = range.$1; i < range.$2; i++) {
      chars[i] = _CharStyle(
        bold: chars[i].bold,
        italic: _toggled(allOn, a.italic),
        underline: chars[i].underline,
        color: chars[i].color,
        fontFamily: chars[i].fontFamily,
        sizeScale: chars[i].sizeScale,
      );
    }
    return _collapse(a.text, chars);
  }

  List<TextRun>? toggleUnderline(TextAnnotation a, int start, int end) {
    final range = _range(a.text, start, end);
    if (range == null) return a.runs;
    final chars = _expand(a);
    final allOn = chars.sublist(range.$1, range.$2).every((c) => (c.underline ?? a.underline) == true);
    for (var i = range.$1; i < range.$2; i++) {
      chars[i] = _CharStyle(
        bold: chars[i].bold,
        italic: chars[i].italic,
        underline: _toggled(allOn, a.underline),
        color: chars[i].color,
        fontFamily: chars[i].fontFamily,
        sizeScale: chars[i].sizeScale,
      );
    }
    return _collapse(a.text, chars);
  }

  /// `null` means "same as the annotation base". An explicit `false` is only
  /// stored when the base style is on and this range must turn it off.
  bool? _toggled(bool allOn, bool base) {
    final next = !allOn;
    if (next == base) return null;
    return next;
  }

  /// Move [annotation]'s runs onto [newText] after an insert, delete, or
  /// replacement. Inserted characters inherit the style at the edit point.
  /// Unstyled annotations stay unstyled. Call this before assigning [newText].
  List<TextRun>? retarget(TextAnnotation annotation, String newText) {
    final oldText = annotation.text;
    if (oldText == newText) return annotation.runs;
    final runs = annotation.runs;
    if (runs == null || runs.isEmpty || newText.isEmpty) return null;

    final oldStyles = _expand(annotation);
    var prefix = 0;
    final maxPrefix = oldText.length < newText.length ? oldText.length : newText.length;
    while (prefix < maxPrefix && oldText.codeUnitAt(prefix) == newText.codeUnitAt(prefix)) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < oldText.length - prefix &&
        suffix < newText.length - prefix &&
        oldText.codeUnitAt(oldText.length - 1 - suffix) ==
            newText.codeUnitAt(newText.length - 1 - suffix)) {
      suffix++;
    }
    // Don't split a grapheme cluster at the edit boundary.
    final prefixSnap = _graphemeStart(oldText, prefix);
    final newPrefix = _graphemeStart(newText, prefix);
    final sharedPrefix = prefixSnap < newPrefix ? prefixSnap : newPrefix;

    final next = <_CharStyle>[];
    for (var i = 0; i < sharedPrefix && i < oldStyles.length; i++) {
      next.add(oldStyles[i]);
    }
    final inserted = newText.length - suffix - sharedPrefix;
    final removed = oldText.length - suffix - sharedPrefix;
    // A pure insertion inherits the character before the caret. A replacement
    // inherits the first character that was replaced.
    final inheritIndex = inserted > 0 && removed <= 0 && sharedPrefix > 0
        ? sharedPrefix - 1
        : sharedPrefix;
    final inherit = oldStyles.isEmpty
        ? const _CharStyle()
        : oldStyles[inheritIndex.clamp(0, oldStyles.length - 1)];
    final newMid = inserted < 0 ? 0 : inserted;
    for (var i = 0; i < newMid; i++) {
      next.add(inherit);
    }
    final suffixStart = oldText.length - suffix;
    for (var i = 0; i < suffix; i++) {
      final index = suffixStart + i;
      if (index >= 0 && index < oldStyles.length) next.add(oldStyles[index]);
    }
    while (next.length < newText.length) {
      next.add(inherit);
    }
    if (next.length > newText.length) {
      next.removeRange(newText.length, next.length);
    }
    return _collapse(newText, next);
  }

  // ── Internal helpers ────────────────────────────────────────────────────

  (int, int)? _range(String text, int start, int end) {
    if (start >= end || start < 0 || end > text.length) return null;
    final snapped = _snapToGraphemes(text, start, end);
    if (snapped.$1 >= snapped.$2 || snapped.$2 > text.length) return null;
    return snapped;
  }

  /// Expand a range that lands inside a grapheme (combining mark or surrogate
  /// pair) so the cluster is styled together.
  (int, int) _snapToGraphemes(String text, int start, int end) {
    return (_graphemeStart(text, start), _graphemeEnd(text, end));
  }

  int _graphemeStart(String text, int offset) {
    if (offset <= 0) return 0;
    if (offset >= text.length) return text.length;
    var unit = 0;
    for (final grapheme in text.characters) {
      final next = unit + grapheme.length;
      if (offset > unit && offset < next) return unit;
      if (offset == unit) return unit;
      unit = next;
    }
    return offset;
  }

  int _graphemeEnd(String text, int offset) {
    if (offset <= 0) return 0;
    if (offset >= text.length) return text.length;
    var unit = 0;
    for (final grapheme in text.characters) {
      final next = unit + grapheme.length;
      if (offset > unit && offset < next) return next;
      if (offset == next || offset == unit) return offset;
      unit = next;
    }
    return offset;
  }

  /// Expand the annotation's runs (or base style) into a per-character style
  /// list so we can apply/toggle styles at arbitrary offsets.
  List<_CharStyle> _expand(TextAnnotation a) {
    final runs = a.runs;
    if (runs == null || runs.isEmpty) {
      return List.generate(a.text.length, (_) => const _CharStyle());
    }
    final result = <_CharStyle>[];
    for (final r in runs) {
      for (var i = 0; i < r.text.length; i++) {
        result.add(_CharStyle(
          bold: r.bold,
          italic: r.italic,
          underline: r.underline,
          color: r.color,
          fontFamily: r.fontFamily,
          sizeScale: r.sizeScale,
        ));
      }
    }
    // Pad or trim if runs text doesn't match annotation text exactly.
    while (result.length < a.text.length) {
      result.add(const _CharStyle());
    }
    return result.sublist(0, a.text.length);
  }

  /// Collapse a per-character style list back into a compact runs list.
  /// Returns null (plain mode) if all chars have no overrides.
  List<TextRun>? _collapse(String text, List<_CharStyle> chars) {
    if (chars.isEmpty) return null;
    final runs = <TextRun>[];
    var runStart = 0;
    for (var i = 1; i <= chars.length; i++) {
      if (i == chars.length || chars[i] != chars[runStart]) {
        final c = chars[runStart];
        runs.add(TextRun(
          text.substring(runStart, i),
          bold: c.bold,
          italic: c.italic,
          underline: c.underline,
          color: c.color,
          fontFamily: c.fontFamily,
          sizeScale: c.sizeScale,
        ));
        runStart = i;
      }
    }
    // If there's only one run with no overrides, return null (plain mode).
    if (runs.length == 1 && runs[0]._isDefault) return null;
    return runs;
  }
}

class _CharStyle {
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final Color? color;
  final String? fontFamily;
  final double? sizeScale;

  const _CharStyle({
    this.bold,
    this.italic,
    this.underline,
    this.color,
    this.fontFamily,
    this.sizeScale,
  });

  @override
  bool operator ==(Object other) =>
      other is _CharStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.color == color &&
      other.fontFamily == fontFamily &&
      other.sizeScale == sizeScale;

  @override
  int get hashCode => Object.hash(bold, italic, underline, color, fontFamily, sizeScale);
}

extension on TextRun {
  bool get _isDefault =>
      bold == null &&
      italic == null &&
      underline == null &&
      color == null &&
      fontFamily == null &&
      sizeScale == null;
}
