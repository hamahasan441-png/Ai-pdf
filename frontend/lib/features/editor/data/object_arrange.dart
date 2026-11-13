import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/form_field_annotation.dart';

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

/// Where one mark sits against the page. [hCenter] and [vCenter] move one
/// axis; both axes at once is [centerAnnotationOnPage].
enum PageEdge { left, right, top, bottom, hCenter, vCenter }

/// Slides [annotation] so the named edge (or centre) meets the page.
/// Already there, locked, or hidden: nothing moves.
bool alignAnnotationToPage(EditorAnnotation annotation, PageEdge edge) {
  if (!annotation.visible || annotation.locked) return false;
  final box = annotation.bounds;
  final dx = switch (edge) {
    PageEdge.left => -box.left,
    PageEdge.right => 1 - box.right,
    PageEdge.hCenter => 0.5 - box.center.dx,
    _ => 0.0,
  };
  final dy = switch (edge) {
    PageEdge.top => -box.top,
    PageEdge.bottom => 1 - box.bottom,
    PageEdge.vCenter => 0.5 - box.center.dy,
    _ => 0.0,
  };
  if (dx.abs() < 1e-6 && dy.abs() < 1e-6) return false;
  annotation.translate(Offset(dx, dy));
  return true;
}

/// A real form widget does not fade: its appearance is the field, not ink.
bool supportsOpacity(EditorAnnotation item) => item is! FormFieldAnnotation;

/// Sets the opacity of any mark that actually paints it. Clamped so a mark
/// cannot be made invisible by the slider (hide still does that).
bool setAnnotationOpacity(EditorAnnotation item, double opacity) {
  if (!item.visible || item.locked || !supportsOpacity(item) || !opacity.isFinite) return false;
  final next = opacity.clamp(0.1, 1.0);
  if ((item.opacity - next).abs() < 0.001) return false;
  item.opacity = next;
  return true;
}

/// Gives every mark but the topmost the topmost one's width and/or height.
/// [paintOrder] is the page list, back to front. The front-most visible
/// unlocked mark is the reference, the same idea as FlexiPDF's "make same
/// size" against the object in front. Returns how many marks changed.
int matchAnnotationSize(Iterable<EditorAnnotation> paintOrder, {required bool width, required bool height}) {
  if (!width && !height) return 0;
  final targets = [for (final item in paintOrder) if (item.visible && !item.locked) item];
  if (targets.length < 2) return 0;
  final ref = targets.last.bounds;
  if (width && ref.width.abs() < 1e-4) return 0;
  if (height && ref.height.abs() < 1e-4) return 0;
  var changed = 0;
  for (final item in targets.take(targets.length - 1)) {
    final box = item.bounds;
    final w = width ? ref.width.abs() : box.width.abs();
    final h = height ? ref.height.abs() : box.height.abs();
    if (w < 1e-4 || h < 1e-4) continue;
    if ((box.width - w).abs() < 1e-4 && (box.height - h).abs() < 1e-4) continue;
    // A text box with no frame becomes a frame, so "same width" wraps it
    // instead of only changing the type size.
    if (item is TextAnnotation && width && item.width == null) {
      item.width = w.clamp(0.02, 0.98);
    }
    item.scaleTo(Rect.fromLTWH(box.left, box.top, w, h));
    changed++;
  }
  return changed;
}
