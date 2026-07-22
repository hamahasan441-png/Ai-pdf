import 'dart:ui' show Rect;

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';

/// A rectangular region marked for redaction (Phase 17).
///
/// [rect] is in the normalised 0..1 page space shared by the rest of the
/// editor. [label] is optional metadata (e.g. "PII", "SSN") for an audit trail.
class RedactionRegion {
  final Rect rect;
  final String? label;

  const RedactionRegion(this.rect, {this.label});
}

/// The result of burning redactions into a page.
class RedactionResult {
  /// Text-layer elements that survive (were NOT covered by any region).
  final List<PdfTextElement> remainingText;

  /// Indices (into the original list) of the elements that were removed.
  final List<int> removedIndices;

  /// Opaque rectangles to paint over the page (overlapping regions merged).
  final List<Rect> coverRects;

  const RedactionResult({
    required this.remainingText,
    required this.removedIndices,
    required this.coverRects,
  });

  int get removedCount => removedIndices.length;
}

/// True redaction for the editor (Phase 17).
///
/// A common mistake in PDF tools is to draw a black box over text and call it
/// "redacted" — the text underneath is still selectable and copyable. This
/// service performs *real* redaction: any native text‑layer element that
/// intersects a redaction region is **removed** from the text layer, so the
/// covered content can no longer be searched, selected, or extracted. It also
/// returns opaque cover rectangles (overlapping regions merged into as few
/// rects as possible) to paint on the page and burn into the export raster.
///
/// Pure Dart + `dart:ui` geometry only → fully unit‑testable and isolate‑safe.
class RedactionService {
  const RedactionService();

  /// Fraction of a text element's area that must be covered for it to count as
  /// redacted. A tiny clip (e.g. a region just grazing an element) shouldn't
  /// wipe an entire line, so the default requires meaningful overlap.
  static const double coverageThreshold = 0.15;

  /// Burn [regions] into a page's [elements].
  RedactionResult apply(
    List<PdfTextElement> elements,
    List<RedactionRegion> regions,
  ) {
    final remaining = <PdfTextElement>[];
    final removed = <int>[];

    for (var i = 0; i < elements.length; i++) {
      if (_isCovered(elements[i].rect, regions)) {
        removed.add(i);
      } else {
        remaining.add(elements[i]);
      }
    }

    return RedactionResult(
      remainingText: remaining,
      removedIndices: removed,
      coverRects: mergeOverlapping([for (final r in regions) r.rect]),
    );
  }

  /// Indices of elements that would be redacted (preview without mutating).
  List<int> coveredElements(
    List<PdfTextElement> elements,
    List<RedactionRegion> regions,
  ) {
    final out = <int>[];
    for (var i = 0; i < elements.length; i++) {
      if (_isCovered(elements[i].rect, regions)) out.add(i);
    }
    return out;
  }

  /// Merge a set of rects so overlapping/touching ones collapse into their
  /// bounding union. Repeats until no more merges happen (handles chains).
  List<Rect> mergeOverlapping(List<Rect> rects) {
    final result = <Rect>[for (final r in rects) r];
    var merged = true;
    while (merged) {
      merged = false;
      outer:
      for (var i = 0; i < result.length; i++) {
        for (var j = i + 1; j < result.length; j++) {
          if (_overlapsOrTouches(result[i], result[j])) {
            final union = result[i].expandToInclude(result[j]);
            result.removeAt(j);
            result[i] = union;
            merged = true;
            break outer;
          }
        }
      }
    }
    return result;
  }

  bool _isCovered(Rect element, List<RedactionRegion> regions) {
    if (element.width <= 0 || element.height <= 0) {
      // Degenerate element: covered if any region contains its top-left.
      for (final region in regions) {
        if (region.rect.contains(element.topLeft)) return true;
      }
      return false;
    }
    final area = element.width * element.height;
    for (final region in regions) {
      final inter = element.intersect(region.rect);
      if (inter.width <= 0 || inter.height <= 0) continue;
      final coveredFraction = (inter.width * inter.height) / area;
      if (coveredFraction >= coverageThreshold) return true;
    }
    return false;
  }

  bool _overlapsOrTouches(Rect a, Rect b) {
    return a.left <= b.right &&
        b.left <= a.right &&
        a.top <= b.bottom &&
        b.top <= a.bottom;
  }
}
