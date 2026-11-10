import 'package:flutter/material.dart';

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';

/// A box in millimetres, measured from the top-left of the page as it is shown.
class MillimetreBox {
  final double left;
  final double top;
  final double width;
  final double height;

  const MillimetreBox({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}

/// Reads a millimetre a person typed. A comma is a decimal mark, as on a
/// German keyboard. Empty or nonsense is null.
double? parseMillimetres(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

/// One decimal, which is a tenth of a millimetre.
String formatMillimetres(double value) {
  if (!value.isFinite) return '';
  return value.toStringAsFixed(1);
}

/// The box of [bounds] on a page of [pageWidthPt] × [pageHeightPt].
/// Null when the page size is not known yet.
MillimetreBox? millimetreBoxOf(
  Rect bounds, {
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  if (pageWidthPt <= 1 || pageHeightPt <= 1 || !pageWidthPt.isFinite || !pageHeightPt.isFinite) {
    return null;
  }
  if (!bounds.left.isFinite || !bounds.top.isFinite || !bounds.width.isFinite || !bounds.height.isFinite) {
    return null;
  }
  double mm(double norm, double page) => norm * page * 25.4 / 72.0;
  return MillimetreBox(
    left: mm(bounds.left, pageWidthPt),
    top: mm(bounds.top, pageHeightPt),
    width: mm(bounds.width.abs(), pageWidthPt),
    height: mm(bounds.height.abs(), pageHeightPt),
  );
}

/// Moves and resizes [item] so it sits at [box]. A side typed as 0 keeps the
/// object's own size on that side, so a line can be placed without inventing
/// a height. Locked and hidden marks are left alone.
///
/// Wrapping text keeps its type size and takes the new width; its height
/// follows the words. Everything else takes the box exactly.
bool placeByMillimetres(
  EditorAnnotation item,
  MillimetreBox box, {
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  if (item.locked || !item.visible) return false;
  if (!box.left.isFinite || !box.top.isFinite || !box.width.isFinite || !box.height.isFinite) return false;
  if (box.width < 0 || box.height < 0) return false;
  final current = millimetreBoxOf(item.bounds, pageWidthPt: pageWidthPt, pageHeightPt: pageHeightPt);
  if (current == null) return false;
  final width = box.width >= 0.05 ? box.width : (current.width >= 0.05 ? current.width : 0.05);
  final height = box.height >= 0.05 ? box.height : (current.height >= 0.05 ? current.height : 0.05);
  final next = _rectFromMillimetres(
    MillimetreBox(left: box.left, top: box.top, width: width, height: height),
    pageWidthPt: pageWidthPt,
    pageHeightPt: pageHeightPt,
  );
  if (next == null) return false;
  item.scaleTo(next);
  return true;
}

Rect? _rectFromMillimetres(
  MillimetreBox box, {
  required double pageWidthPt,
  required double pageHeightPt,
}) {
  if (pageWidthPt <= 1 || pageHeightPt <= 1) return null;
  if (box.width <= 0 || box.height <= 0) return null;
  double norm(double mm, double page) => (mm * 72.0 / 25.4) / page;
  final left = norm(box.left, pageWidthPt).clamp(0.0, 1.0);
  final top = norm(box.top, pageHeightPt).clamp(0.0, 1.0);
  final right = norm(box.left + box.width, pageWidthPt).clamp(left, 1.0);
  final bottom = norm(box.top + box.height, pageHeightPt).clamp(top, 1.0);
  if (right - left < 1e-6 && bottom - top < 1e-6) return null;
  return Rect.fromLTRB(left, top, right, bottom);
}

/// Visible marks, in paint order. Hidden ones are skipped so Tab never
/// lands on a mark the page is not showing. Locked ones stay: they can
/// still be unlocked.
List<EditorAnnotation> selectableMarks(Iterable<EditorAnnotation> items) =>
    [for (final item in items) if (item.visible) item];

/// The next visible mark after [current], wrapping around the page.
/// When nothing is selected, the first (or, going backward, the last).
EditorAnnotation? cycleMark(
  Iterable<EditorAnnotation> items,
  EditorAnnotation? current, {
  required bool backward,
}) {
  final list = selectableMarks(items);
  if (list.isEmpty) return null;
  final index = current == null ? -1 : list.indexWhere((item) => identical(item, current));
  if (index < 0) return backward ? list.last : list.first;
  final count = list.length;
  final next = backward ? (index - 1 + count) % count : (index + 1) % count;
  return list[next];
}
