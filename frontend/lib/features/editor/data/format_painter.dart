import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/text_markup_annotation.dart';

/// The look copied from one object, the way a format painter carries it.
///
/// Only what the object actually has is set. Ink keeps its colour: a stroke's
/// colour cannot change after it is drawn, so the painter takes its opacity.
class CopiedStyle {
  final Color? color;
  final double? strokeWidth;
  final double? opacity;
  final double? fontSize;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final bool? filled;

  const CopiedStyle({
    this.color,
    this.strokeWidth,
    this.opacity,
    this.fontSize,
    this.bold,
    this.italic,
    this.underline,
    this.filled,
  });

  bool get isEmpty =>
      color == null &&
      strokeWidth == null &&
      opacity == null &&
      fontSize == null &&
      bold == null &&
      italic == null &&
      underline == null &&
      filled == null;
}

CopiedStyle copyStyle(EditorAnnotation item) {
  if (item is TextAnnotation) {
    return CopiedStyle(
      color: item.color,
      opacity: item.opacity,
      fontSize: item.size,
      bold: item.bold,
      italic: item.italic,
      underline: item.underline,
    );
  }
  if (item is ShapeAnnotation) {
    return CopiedStyle(color: item.color, opacity: item.opacity, strokeWidth: item.width, filled: item.filled);
  }
  if (item is TextMarkupAnnotation) {
    return CopiedStyle(color: item.color, opacity: item.opacity);
  }
  if (item is StampAnnotation) {
    return CopiedStyle(color: item.color, opacity: item.opacity);
  }
  return CopiedStyle(opacity: item.opacity);
}

bool _sameColor(Color a, Color b) => a.toARGB32() == b.toARGB32();

/// Paints [style] onto [item]. A locked object is left alone. Returns
/// whether anything changed, so an unchanged tap is not an undo step.
bool applyStyle(EditorAnnotation item, CopiedStyle style) {
  if (item.locked || style.isEmpty) return false;
  var changed = false;
  if (style.opacity != null && (item.opacity - style.opacity!).abs() > 0.001) {
    item.opacity = style.opacity!;
    changed = true;
  }
  if (item is TextAnnotation) {
    final color = style.color;
    if (color != null && !_sameColor(item.color, color)) {
      item.color = color;
      changed = true;
    }
    if (style.fontSize != null && (item.size - style.fontSize!).abs() > 0.01) {
      item.size = style.fontSize!;
      changed = true;
    }
    if (style.bold != null && item.bold != style.bold) {
      item.bold = style.bold!;
      changed = true;
    }
    if (style.italic != null && item.italic != style.italic) {
      item.italic = style.italic!;
      changed = true;
    }
    if (style.underline != null && item.underline != style.underline) {
      item.underline = style.underline!;
      changed = true;
    }
    return changed;
  }
  if (item is ShapeAnnotation) {
    final color = style.color;
    if (color != null && !_sameColor(item.color, color)) {
      item.color = color;
      changed = true;
    }
    if (style.strokeWidth != null && (item.width - style.strokeWidth!).abs() > 0.01) {
      item.width = style.strokeWidth!;
      changed = true;
    }
    if (style.filled != null && item.filled != style.filled) {
      item.filled = style.filled!;
      changed = true;
    }
    return changed;
  }
  if (item is TextMarkupAnnotation) {
    final color = style.color;
    if (color != null && !_sameColor(item.color, color)) {
      item.color = color;
      changed = true;
    }
  } else if (item is StampAnnotation) {
    final color = style.color;
    if (color != null && !_sameColor(item.color, color)) {
      item.color = color;
      changed = true;
    }
  }
  return changed;
}
