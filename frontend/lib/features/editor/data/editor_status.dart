import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';

/// Zoom relative to the fitted page, as a whole percent.
int zoomPercent(double scale) {
  if (!scale.isFinite || scale <= 0) return 100;
  return (scale * 100).round().clamp(5, 800);
}

/// The next zoom step, kept inside what the page can still be read at.
double nextZoom(double scale, {required bool zoomIn}) {
  final current = !scale.isFinite || scale <= 0 ? 1.0 : scale;
  final next = current * (zoomIn ? 1.25 : 0.8);
  return next.clamp(0.5, 5.0);
}

class PaperSize {
  final String? name;
  final String millimetres;

  const PaperSize({required this.name, required this.millimetres});

  String get label => name == null ? millimetres : '$name · $millimetres';
}

/// Names a page when it is a standard size, and always gives it in millimetres.
/// [widthPt] and [heightPt] are the page as it is shown, in PDF points.
PaperSize paperSize(double widthPt, double heightPt) {
  if (widthPt <= 1 || heightPt <= 1 || !widthPt.isFinite || !heightPt.isFinite) {
    return const PaperSize(name: null, millimetres: '');
  }
  return PaperSize(
    name: _paperName(widthPt, heightPt),
    millimetres: '${_mm(widthPt, 0)} × ${_mm(heightPt, 0)} mm',
  );
}

/// The selected box as width × height in millimetres. Empty when the page
/// size is not known yet.
String selectionMillimetres(Rect bounds, {required double pageWidthPt, required double pageHeightPt}) {
  if (pageWidthPt <= 1 || pageHeightPt <= 1) return '';
  final w = bounds.width.abs() * pageWidthPt;
  final h = bounds.height.abs() * pageHeightPt;
  if (w < 0.5 && h < 0.5) return '';
  return '${_mm(w, 1)} × ${_mm(h, 1)} mm';
}

bool _near(double a, double b) => (a - b).abs() <= 6;

String? _paperName(double width, double height) {
  final short = math.min(width, height);
  final long = math.max(width, height);
  const sizes = <(String, double, double)>[
    ('A3', 841.89, 1190.55),
    ('A4', 595.28, 841.89),
    ('A5', 419.53, 595.28),
    ('Letter', 612, 792),
    ('Legal', 612, 1008),
    ('Tabloid', 792, 1224),
  ];
  for (final (name, w, h) in sizes) {
    if (_near(short, math.min(w, h)) && _near(long, math.max(w, h))) return name;
  }
  return null;
}

String _mm(double points, int digits) => (points * 25.4 / 72.0).toStringAsFixed(digits);

/// Text, a picture and a stamp can turn. A line or a highlight cannot.
bool canQuarterTurn(EditorAnnotation item) =>
    !item.locked && (item is TextAnnotation || item is ImageAnnotation || item is StampAnnotation);

/// Turns [item] a quarter turn counter-clockwise. Returns whether it turned.
bool quarterTurn(EditorAnnotation item) {
  if (!canQuarterTurn(item)) return false;
  if (item is TextAnnotation) {
    item.rotation = _wrap(item.rotation + math.pi / 2);
  } else if (item is ImageAnnotation) {
    item.rotation = _wrap(item.rotation + math.pi / 2);
  } else if (item is StampAnnotation) {
    item.rotation = _wrap(item.rotation + math.pi / 2);
  }
  return true;
}

double _wrap(double radians) {
  final turns = radians % (math.pi * 2);
  return turns < 0 ? turns + math.pi * 2 : turns;
}
