import 'package:flutter/widgets.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/annotation_bounds_service.dart';

class SelectionSnapGuides {
  final double? guideX;
  final double? guideY;

  const SelectionSnapGuides({this.guideX, this.guideY});
}

/// Mutation helpers for moving, resizing, cloning, snapping, and aligning
/// editor annotations.
///
/// Per-object geometry (translate / scaleTo / clone) now lives on the
/// [EditorAnnotation] objects themselves via the unified Transformable
/// contract; this service delegates to it so every current and future object
/// type is handled uniformly, and keeps the higher-level snapping / alignment
/// orchestration that spans multiple objects.
class SelectionService {
  const SelectionService();

  void moveAnnotation(EditorAnnotation a, Offset d) {
    a.translate(d);
  }

  void moveSelected(EditorAnnotation sel, Offset deltaNorm) {
    sel.translate(deltaNorm);
  }

  void scaleSelectedTo(
    EditorAnnotation sel,
    Rect nextBounds,
    AnnotationBoundsService bounds,
  ) {
    sel.scaleTo(nextBounds);
  }

  SelectionSnapGuides snapSelected(
    EditorAnnotation sel,
    AnnotationBoundsService bounds, {
    List<EditorAnnotation> others = const [],
  }) {
    // 1) Object-to-object snapping takes priority: align the dragged object's
    //    edges/centre to any other object's edges/centre (like desktop editors).
    final obj = _snapToObjects(sel, bounds, others);
    double? gx = obj.guideX;
    double? gy = obj.guideY;

    // 2) Fall back to page guide lines (thirds + edges) per axis not yet snapped.
    const threshold = 0.014;

    if (gx == null) {
      final b = bounds.boundsOf(sel);
      for (final line in const [0.25, 0.5, 0.75]) {
        if ((b.center.dx - line).abs() < threshold) {
          moveAnnotation(sel, Offset(line - b.center.dx, 0));
          gx = line;
          break;
        }
      }
      if (gx == null) {
        final b1 = bounds.boundsOf(sel);
        if (b1.left.abs() < threshold) {
          moveAnnotation(sel, Offset(-b1.left, 0));
          gx = 0;
        } else if ((b1.right - 1).abs() < threshold) {
          moveAnnotation(sel, Offset(1 - b1.right, 0));
          gx = 1;
        }
      }
    }

    if (gy == null) {
      final b2 = bounds.boundsOf(sel);
      for (final line in const [0.25, 0.5, 0.75]) {
        if ((b2.center.dy - line).abs() < threshold) {
          moveAnnotation(sel, Offset(0, line - b2.center.dy));
          gy = line;
          break;
        }
      }
      if (gy == null) {
        final b3 = bounds.boundsOf(sel);
        if (b3.top.abs() < threshold) {
          moveAnnotation(sel, Offset(0, -b3.top));
          gy = 0;
        } else if ((b3.bottom - 1).abs() < threshold) {
          moveAnnotation(sel, Offset(0, 1 - b3.bottom));
          gy = 1;
        }
      }
    }

    return SelectionSnapGuides(guideX: gx, guideY: gy);
  }

  /// Snap [sel] to the nearest edge/centre of any other object within a small
  /// threshold, returning the guide line positions (normalised) that were hit.
  /// Pure geometry: compares left/centre/right and top/centre/bottom of [sel]
  /// against the same anchors on every other object and applies the closest.
  SelectionSnapGuides _snapToObjects(
    EditorAnnotation sel,
    AnnotationBoundsService bounds,
    List<EditorAnnotation> others,
  ) {
    if (others.isEmpty) return const SelectionSnapGuides();
    const threshold = 0.012;
    final b = bounds.boundsOf(sel);
    final selXs = [b.left, b.center.dx, b.right];
    final selYs = [b.top, b.center.dy, b.bottom];

    double? gx;
    double? gy;
    double? offX;
    double? offY;
    double bestX = threshold;
    double bestY = threshold;

    for (final o in others) {
      if (identical(o, sel)) continue;
      final r = bounds.boundsOf(o);
      for (final rx in [r.left, r.center.dx, r.right]) {
        for (final sx in selXs) {
          final d = (rx - sx).abs();
          if (d < bestX) {
            bestX = d;
            gx = rx;
            offX = rx - sx;
          }
        }
      }
      for (final ry in [r.top, r.center.dy, r.bottom]) {
        for (final sy in selYs) {
          final d = (ry - sy).abs();
          if (d < bestY) {
            bestY = d;
            gy = ry;
            offY = ry - sy;
          }
        }
      }
    }

    if (offX != null || offY != null) {
      moveAnnotation(sel, Offset(offX ?? 0, offY ?? 0));
    }
    return SelectionSnapGuides(guideX: gx, guideY: gy);
  }

  bool resizeSelectedShape(EditorAnnotation sel, Offset newEndNorm) {
    if (sel is! ShapeAnnotation) return false;
    sel.end = Offset(newEndNorm.dx.clamp(0.0, 1.0), newEndNorm.dy.clamp(0.0, 1.0));
    return true;
  }

  bool resizeSelectedText(EditorAnnotation sel, double factor) {
    if (sel is! TextAnnotation) return false;
    sel.size = (sel.size * factor).clamp(0.008, 0.2);
    return true;
  }

  EditorAnnotation? cloneAnnotation(EditorAnnotation sel, double d) {
    return sel.clone(shift: d);
  }

  void bringToFront(EditorAnnotation sel, List<EditorAnnotation> items) {
    items.remove(sel);
    items.add(sel);
  }

  void sendToBack(EditorAnnotation sel, List<EditorAnnotation> items) {
    items.remove(sel);
    items.insert(0, sel);
  }

  void alignAnnotations(
    Set<EditorAnnotation> selection,
    String how,
    AnnotationBoundsService bounds,
  ) {
    if (selection.length < 2) return;
    final rects = {for (final a in selection) a: bounds.boundsOf(a)};
    Rect group = rects.values.first;
    for (final r in rects.values) {
      group = group.expandToInclude(r);
    }
    for (final a in selection) {
      final r = rects[a]!;
      double dx = 0;
      double dy = 0;
      switch (how) {
        case 'left':
          dx = group.left - r.left;
          break;
        case 'hcenter':
          dx = group.center.dx - r.center.dx;
          break;
        case 'right':
          dx = group.right - r.right;
          break;
        case 'top':
          dy = group.top - r.top;
          break;
        case 'vcenter':
          dy = group.center.dy - r.center.dy;
          break;
        case 'bottom':
          dy = group.bottom - r.bottom;
          break;
      }
      moveAnnotation(a, Offset(dx, dy));
    }
  }

  void distributeAnnotations(
    List<EditorAnnotation> selection,
    Axis axis,
    AnnotationBoundsService bounds,
  ) {
    if (selection.length < 3) return;
    final rects = {for (final a in selection) a: bounds.boundsOf(a)};
    selection.sort((p, q) => axis == Axis.horizontal
        ? rects[p]!.center.dx.compareTo(rects[q]!.center.dx)
        : rects[p]!.center.dy.compareTo(rects[q]!.center.dy));
    final first = rects[selection.first]!.center;
    final last = rects[selection.last]!.center;
    final step = (axis == Axis.horizontal ? (last.dx - first.dx) : (last.dy - first.dy)) /
        (selection.length - 1);
    for (var i = 1; i < selection.length - 1; i++) {
      final a = selection[i];
      final c = rects[a]!.center;
      if (axis == Axis.horizontal) {
        moveAnnotation(a, Offset(first.dx + step * i - c.dx, 0));
      } else {
        moveAnnotation(a, Offset(0, first.dy + step * i - c.dy));
      }
    }
  }
}
