import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Distance on a page, in the units a German editor shows by default.
///
/// [a] and [b] are 0..1 from the displayed top left. The page size is in
/// PDF points (1/72 inch), so the number does not depend on the zoom.
double measurePoints(
  Offset a,
  Offset b, {
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  if (pageWidthPt <= 0 || pageHeightPt <= 0) return 0;
  final dx = (a.dx - b.dx) * pageWidthPt;
  final dy = (a.dy - b.dy) * pageHeightPt;
  return math.sqrt(dx * dx + dy * dy);
}

/// [points] as millimetres, the way a dimension line is labelled.
String formatMillimetres(double points) {
  final mm = points * 25.4 / 72.0;
  if (mm >= 100) return '${mm.toStringAsFixed(0)} mm';
  if (mm >= 10) return '${mm.toStringAsFixed(1)} mm';
  return '${mm.toStringAsFixed(2)} mm';
}

String measureLabel(
  Offset a,
  Offset b, {
  required double pageWidthPt,
  required double pageHeightPt,
}) =>
    formatMillimetres(measurePoints(a, b, pageWidthPt: pageWidthPt, pageHeightPt: pageHeightPt));
