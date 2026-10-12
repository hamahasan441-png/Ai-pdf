import 'dart:ui' show Color, Offset, Rect;

import 'package:ai_pdf/features/editor/data/text_layer_extraction_service.dart';
import 'package:ai_pdf/features/editor/domain/entities/editor_tool.dart';
import 'package:ai_pdf/features/editor/domain/entities/text_markup_annotation.dart';
import 'package:ai_pdf/features/editor/domain/services/text_selection_service.dart';

/// Builds highlight / underline / strikeout / squiggly marks.
///
/// When the page has a text layer (the same idea as pdf.js `getTextContent`),
/// the drag selects the words between its endpoints, the way Foxit and Acrobat
/// do. A scanned page with no text layer falls back to the drag rectangle.
class TextMarkupFactory {
  final TextSelectionService selection;

  const TextMarkupFactory({this.selection = const TextSelectionService()});

  bool isMarkupTool(EditTool tool) => kindFor(tool) != null;

  TextMarkupKind? kindFor(EditTool tool) {
    switch (tool) {
      case EditTool.highlight:
        return TextMarkupKind.highlight;
      case EditTool.underline:
        return TextMarkupKind.underline;
      case EditTool.strikeout:
        return TextMarkupKind.strikeout;
      case EditTool.squiggly:
        return TextMarkupKind.squiggly;
      default:
        return null;
    }
  }

  List<Rect> previewRects({
    required EditTool tool,
    required Offset start,
    required Offset end,
    required List<PdfTextElement> elements,
    Color color = const Color(0xFFFFEB3B),
  }) {
    return fromDrag(
          tool: tool,
          start: start,
          end: end,
          elements: elements,
          color: color,
        )?.rects ??
        const [];
  }

  TextMarkupAnnotation? fromDrag({
    required EditTool tool,
    required Offset start,
    required Offset end,
    required List<PdfTextElement> elements,
    required Color color,
  }) {
    final kind = kindFor(tool);
    if (kind == null) return null;
    if (elements.isNotEmpty) {
      final sel = selection.selectRange(elements, start, end);
      if (sel.rects.isEmpty) return null;
      return TextMarkupAnnotation(
        kind: kind,
        rects: sel.rects,
        color: color,
        text: sel.text,
      );
    }
    var rect = Rect.fromPoints(start, end);
    if (rect.width < 0.012 && rect.height >= 0.02) {
      final mid = (rect.left + rect.right) / 2;
      rect = Rect.fromLTRB(mid - 0.04, rect.top, mid + 0.04, rect.bottom);
    } else if (rect.height < 0.016) {
      final mid = (rect.top + rect.bottom) / 2;
      rect = Rect.fromLTRB(rect.left, mid - 0.01, rect.right, mid + 0.01);
    }
    rect = Rect.fromLTRB(
      rect.left.clamp(0.0, 1.0),
      rect.top.clamp(0.0, 1.0),
      rect.right.clamp(0.0, 1.0),
      rect.bottom.clamp(0.0, 1.0),
    );
    if (rect.width < 0.01 || rect.height < 0.004) return null;
    return TextMarkupAnnotation(kind: kind, rects: [rect], color: color);
  }
}
