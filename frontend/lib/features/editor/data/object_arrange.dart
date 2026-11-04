import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// About three pixels on an 800 px page. Shift uses the coarser step,
/// the same pair PDF-XChange gives the arrow keys.
const double fineNudge = 0.004;
const double coarseNudge = 0.02;

/// Moves [annotation] by a normalised [delta]. Locked and hidden marks stay.
bool nudgeAnnotation(EditorAnnotation annotation, Offset delta) {
  if (!annotation.visible || annotation.locked || delta == Offset.zero) return false;
  annotation.translate(delta);
  return true;
}

/// Puts the middle of [annotation] on the middle of the page.
/// FlexiPDF does this for a single selected object; align-to-each-other
/// stays the multi-selection tools.
bool centerAnnotationOnPage(EditorAnnotation annotation) {
  if (!annotation.visible || annotation.locked) return false;
  final box = annotation.bounds;
  annotation.translate(Offset(0.5 - box.center.dx, 0.5 - box.center.dy));
  return true;
}
