import 'dart:ui' show Color;

import 'package:ai_pdf/features/editor/data/annotation_serialization.dart';
import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Exports annotations to XFDF format (XML-based Forms Data Format).
///
/// XFDF is the industry standard for exchanging PDF annotations between
/// applications (supported by Acrobat, Foxit, PDF Expert, etc.).
/// This enables round-tripping: export annotations → email → import in
/// another PDF tool → all annotations preserved.
///
/// Currently supports: text annotations, highlights (strokes with highlight=true),
/// shapes (ink, rect, circle), and sticky notes.
class AnnotationExportXfdf {
  const AnnotationExportXfdf();

  /// Export all annotations from [layers] to an XFDF XML string.
  String export(Map<int, PageLayer> layers, {String? documentPath}) {
    final buffer = StringBuffer();
    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<xfdf xmlns="http://ns.adobe.com/xfdf/" xml:space="preserve">');
    if (documentPath != null) {
      buffer.writeln('  <f href="$documentPath"/>');
    }
    buffer.writeln('  <annots>');

    for (final entry in layers.entries) {
      final page = entry.key;
      for (final annot in entry.value.items) {
        final xml = _annotationToXfdf(annot, page);
        if (xml != null) buffer.writeln(xml);
      }
    }

    buffer.writeln('  </annots>');
    buffer.writeln('</xfdf>');
    return buffer.toString();
  }

  String? _annotationToXfdf(EditorAnnotation annot, int page) {
    if (annot is TextAnnotation) return _textToXfdf(annot, page);
    if (annot is StrokeAnnotation) return _strokeToXfdf(annot, page);
    if (annot is ShapeAnnotation) return _shapeToXfdf(annot, page);
    return null;
  }

  String _textToXfdf(TextAnnotation t, int page) {
    final rect = '${(t.pos.dx * 612).toStringAsFixed(2)},'
        '${((1 - t.pos.dy) * 792).toStringAsFixed(2)},'
        '${((t.pos.dx + (t.width ?? 0.3)) * 612).toStringAsFixed(2)},'
        '${((1 - t.pos.dy - (t.height ?? 0.05)) * 792).toStringAsFixed(2)}';
    return '    <freetext page="$page" rect="$rect" '
        'color="${_colorHex(t.color)}" fontsize="${(t.size * 792).round()}">'
        '<contents-richtext>${_escapeXml(t.text)}</contents-richtext>'
        '</freetext>';
  }

  String _strokeToXfdf(StrokeAnnotation s, int page) {
    if (s.highlight) {
      // Highlight annotation
      final points = s.points.map((p) =>
        '${(p.dx * 612).toStringAsFixed(2)},${((1 - p.dy) * 792).toStringAsFixed(2)}'
      ).join(';');
      return '    <highlight page="$page" color="${_colorHex(s.color)}" '
          'coords="$points" opacity="${s.opacity}"/>';
    }
    // Ink annotation
    final points = s.points.map((p) =>
      '${(p.dx * 612).toStringAsFixed(2)},${((1 - p.dy) * 792).toStringAsFixed(2)}'
    ).join(';');
    return '    <ink page="$page" color="${_colorHex(s.color)}" '
        'width="${s.width}" inklist="$points"/>';
  }

  String _shapeToXfdf(ShapeAnnotation s, int page) {
    final rect = '${(s.start.dx * 612).toStringAsFixed(2)},'
        '${((1 - s.start.dy) * 792).toStringAsFixed(2)},'
        '${(s.end.dx * 612).toStringAsFixed(2)},'
        '${((1 - s.end.dy) * 792).toStringAsFixed(2)}';
    final tag = s.type == ShapeType.oval ? 'circle' : 'square';
    return '    <$tag page="$page" rect="$rect" '
        'color="${_colorHex(s.color)}" width="${s.width}"/>';
  }

  String _colorHex(Color c) => '#${c.value.toRadixString(16).substring(2).toUpperCase()}';
  String _escapeXml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}
