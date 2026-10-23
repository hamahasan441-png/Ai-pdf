
import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// PDF text-markup kinds (PDF 32000 annotation subtypes Highlight, Underline,
/// StrikeOut and Squiggly). The same four tools Foxit, Acrobat and the pdf.js
/// editor expose. Each stores one normalised rect per selected word, not a
/// freehand stroke, so the mark hugs the glyphs.
enum TextMarkupKind { highlight, underline, strikeout, squiggly }

class TextMarkupAnnotation extends EditorAnnotation {
  TextMarkupKind kind;
  final List<Rect> rects;
  Color color;

  /// The words under the mark, kept so copy / search can read them back.
  String text;

  TextMarkupAnnotation({
    required this.kind,
    required List<Rect> rects,
    required this.color,
    this.text = '',
    super.id,
  })  : rects = List<Rect>.of(rects);

  @override
  Rect get bounds {
    if (rects.isEmpty) return Rect.zero;
    var r = rects.first;
    for (final next in rects.skip(1)) {
      r = r.expandToInclude(next);
    }
    return r;
  }

  @override
  void translate(Offset delta) {
    for (var i = 0; i < rects.length; i++) {
      final n = rects[i].shift(delta);
      rects[i] = Rect.fromLTRB(
        n.left.clamp(0.0, 1.0),
        n.top.clamp(0.0, 1.0),
        n.right.clamp(0.0, 1.0),
        n.bottom.clamp(0.0, 1.0),
      );
    }
  }

  @override
  void scaleTo(Rect next) {
    final old = bounds;
    final ow = old.width.abs() < 1e-6 ? 1e-6 : old.width;
    final oh = old.height.abs() < 1e-6 ? 1e-6 : old.height;
    for (var i = 0; i < rects.length; i++) {
      final r = rects[i];
      double mapX(double x) => next.left + (x - old.left) / ow * next.width;
      double mapY(double y) => next.top + (y - old.top) / oh * next.height;
      rects[i] = Rect.fromLTRB(
        mapX(r.left).clamp(0.0, 1.0),
        mapY(r.top).clamp(0.0, 1.0),
        mapX(r.right).clamp(0.0, 1.0),
        mapY(r.bottom).clamp(0.0, 1.0),
      );
    }
  }

  @override
  TextMarkupAnnotation clone({double shift = 0, String? id}) {
    final c = TextMarkupAnnotation(
      kind: kind,
      rects: [
        for (final r in rects)
          r.shift(Offset(shift, shift)),
      ],
      color: color,
      text: text,
      id: id,
    );
    c.copyBaseFrom(this);
    return c;
  }

  @override
  void restoreFrom(TextMarkupAnnotation o) {
    kind = o.kind;
    color = o.color;
    text = o.text;
    rects
      ..clear()
      ..addAll(o.rects);
    copyBaseFrom(o);
  }
}
