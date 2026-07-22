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
    if (start >= end || start < 0 || end > annotation.text.length) return annotation.runs;

    // Expand the annotation into per-character runs (materialise if runs==null).
    final chars = _expand(annotation);
    
    // Apply the style override to the selected range.
    for (var i = start; i < end; i++) {
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
    if (start >= end || start < 0 || end > a.text.length) return a.runs;
    final chars = _expand(a);
    final allBold = chars.sublist(start, end).every((c) => c.bold == true);
    for (var i = start; i < end; i++) {
      chars[i] = _CharStyle(
        bold: allBold ? null : true,
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
    if (start >= end || start < 0 || end > a.text.length) return a.runs;
    final chars = _expand(a);
    final all = chars.sublist(start, end).every((c) => c.italic == true);
    for (var i = start; i < end; i++) {
      chars[i] = _CharStyle(
        bold: chars[i].bold,
        italic: all ? null : true,
        underline: chars[i].underline,
        color: chars[i].color,
        fontFamily: chars[i].fontFamily,
        sizeScale: chars[i].sizeScale,
      );
    }
    return _collapse(a.text, chars);
  }

  List<TextRun>? toggleUnderline(TextAnnotation a, int start, int end) {
    if (start >= end || start < 0 || end > a.text.length) return a.runs;
    final chars = _expand(a);
    final all = chars.sublist(start, end).every((c) => c.underline == true);
    for (var i = start; i < end; i++) {
      chars[i] = _CharStyle(
        bold: chars[i].bold,
        italic: chars[i].italic,
        underline: all ? null : true,
        color: chars[i].color,
        fontFamily: chars[i].fontFamily,
        sizeScale: chars[i].sizeScale,
      );
    }
    return _collapse(a.text, chars);
  }

  // ── Internal helpers ────────────────────────────────────────────────────

  /// Expand the annotation's runs (or base style) into a per-character style
  /// list so we can apply/toggle styles at arbitrary offsets.
  List<_CharStyle> _expand(TextAnnotation a) {
    final runs = a.runs;
    if (runs == null || runs.isEmpty) {
      return List.generate(a.text.length, (_) => _CharStyle());
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
      result.add(_CharStyle());
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

  bool get _isDefault =>
      bold == null &&
      italic == null &&
      underline == null &&
      color == null &&
      fontFamily == null &&
      sizeScale == null;

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
