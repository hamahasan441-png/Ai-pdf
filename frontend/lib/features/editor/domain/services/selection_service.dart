import 'package:flutter/widgets.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/annotation_bounds_service.dart';

class SelectionSnapGuides {
  final double? guideX;
  final double? guideY;

  const SelectionSnapGuides({this.guideX, this.guideY});
}

/// Mutation helpers for moving, resizing, cloning, snapping, and aligning
/// editor annotations. These methods intentionally mutate the passed annotation
/// objects so the screen can keep its current state model while the logic moves
/// out of the widget class.
class SelectionService {
  const SelectionService();

  Offset _clampOff(Offset o, [double max = 1.0]) =>
      Offset(o.dx.clamp(0.0, max), o.dy.clamp(0.0, max));

  void moveAnnotation(EditorAnnotation a, Offset d) {
    if (a is ShapeAnnotation) {
      a.start = _clampOff(a.start + d);
      a.end = _clampOff(a.end + d);
    } else if (a is TextAnnotation) {
      a.pos = _clampOff(a.pos + d, 0.98);
    } else if (a is StrokeAnnotation) {
      for (var i = 0; i < a.points.length; i++) {
        a.points[i] = _clampOff(a.points[i] + d);
      }
    }
  }

  void moveSelected(EditorAnnotation sel, Offset deltaNorm) {
    moveAnnotation(sel, deltaNorm);
  }

  void scaleSelectedTo(
    EditorAnnotation sel,
    Rect nextBounds,
    AnnotationBoundsService bounds,
  ) {
    final oldBounds = bounds.boundsOf(sel);
    final ow = oldBounds.width.abs() < 1e-6 ? 1e-6 : oldBounds.width;
    final oh = oldBounds.height.abs() < 1e-6 ? 1e-6 : oldBounds.height;

    double mapX(double x) => nextBounds.left + (x - oldBounds.left) / ow * nextBounds.width;
    double mapY(double y) => nextBounds.top + (y - oldBounds.top) / oh * nextBounds.height;

    if (sel is StrokeAnnotation) {
      for (var i = 0; i < sel.points.length; i++) {
        sel.points[i] = Offset(
          mapX(sel.points[i].dx).clamp(0.0, 1.0),
          mapY(sel.points[i].dy).clamp(0.0, 1.0),
        );
      }
    } else if (sel is ShapeAnnotation) {
      sel.start = Offset(
        mapX(sel.start.dx).clamp(0.0, 1.0),
        mapY(sel.start.dy).clamp(0.0, 1.0),
      );
      sel.end = Offset(
        mapX(sel.end.dx).clamp(0.0, 1.0),
        mapY(sel.end.dy).clamp(0.0, 1.0),
      );
    } else if (sel is TextAnnotation) {
      sel.pos = Offset(nextBounds.left.clamp(0.0, 0.98), nextBounds.top.clamp(0.0, 0.98));
      sel.size = (sel.size * (nextBounds.height / oh)).clamp(0.01, 0.2);
    }
  }

  SelectionSnapGuides snapSelected(
    EditorAnnotation sel,
    AnnotationBoundsService bounds,
  ) {
    const threshold = 0.014;
    double? gx;
    double? gy;

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
    if (sel is ShapeAnnotation) {
      return ShapeAnnotation(
        sel.type,
        Offset(sel.start.dx + d, sel.start.dy + d),
        Offset(sel.end.dx + d, sel.end.dy + d),
        sel.color,
        sel.width,
      );
    }
    if (sel is TextAnnotation) {
      return TextAnnotation(
        Offset(sel.pos.dx + d, sel.pos.dy + d),
        sel.text,
        sel.color,
        sel.size,
        sel.bold,
        italic: sel.italic,
        underline: sel.underline,
        fontFamily: sel.fontFamily,
        textAlign: sel.textAlign,
        textDirection: sel.textDirection,
        lineHeight: sel.lineHeight,
        charSpacing: sel.charSpacing,
        width: sel.width,
        height: sel.height,
        rotation: sel.rotation,
      );
    }
    if (sel is StrokeAnnotation) {
      return StrokeAnnotation(
        sel.points.map((p) => Offset(p.dx + d, p.dy + d)).toList(),
        sel.color,
        sel.width,
        sel.highlight,
      );
    }
    return null;
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
