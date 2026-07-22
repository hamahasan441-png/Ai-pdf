import 'dart:convert' show base64Decode, base64Encode;
import 'dart:ui' show Offset, TextAlign, TextDirection;

import 'package:flutter/material.dart' show Color, Colors;

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';

/// Pure-Dart JSON serialization for the annotation model.
///
/// Design notes:
/// - Additive & backward compatible: new shared props (opacity/locked/visible/
///   zIndex/metadata) are written under stable keys. Files written by an older
///   build simply omit them and are restored with defaults; files written by a
///   newer build are still readable by an older build (unknown keys ignored).
/// - Round-trip safe: fromJson(toJson(x)) recreates an equivalent annotation.
/// - Graceful: fromJson skips corrupt entries rather than throwing so a
///   partially-corrupt save file never blocks the editor from opening.

// ---------------------------------------------------------------------------
// Shared base props
// ---------------------------------------------------------------------------

Map<String, dynamic> _baseToJson(EditorAnnotation a) => {
      'opacity': a.opacity,
      'locked': a.locked,
      'visible': a.visible,
      'zIndex': a.zIndex,
      if (a.metadata.isNotEmpty) 'metadata': a.metadata,
    };

void _applyBase(EditorAnnotation a, Map<String, dynamic> j) {
  a.opacity = (j['opacity'] as num?)?.toDouble() ?? a.opacity;
  a.locked = j['locked'] as bool? ?? a.locked;
  a.visible = j['visible'] as bool? ?? a.visible;
  a.zIndex = (j['zIndex'] as num?)?.toInt() ?? a.zIndex;
  final m = j['metadata'];
  if (m is Map) a.metadata = Map<String, dynamic>.from(m);
}

// ---------------------------------------------------------------------------
// Serialize
// ---------------------------------------------------------------------------

Map<String, dynamic> annotationToJson(EditorAnnotation a) {
  if (a is StrokeAnnotation) return _strokeToJson(a);
  if (a is ShapeAnnotation) return _shapeToJson(a);
  if (a is TextAnnotation) return _textToJson(a);
  if (a is ImageAnnotation) return _imageToJson(a);
  if (a is StampAnnotation) return _stampToJson(a);
  return {'type': 'unknown', 'id': a.id};
}

Map<String, dynamic> _imageToJson(ImageAnnotation im) => {
      'type': 'image',
      'id': im.id,
      'posX': im.pos.dx,
      'posY': im.pos.dy,
      'width': im.width,
      'height': im.height,
      'rotation': im.rotation,
      'label': im.label,
      'bytes': base64Encode(im.bytes),
      ..._baseToJson(im),
    };

Map<String, dynamic> _stampToJson(StampAnnotation st) => {
      'type': 'stamp',
      'id': st.id,
      'posX': st.pos.dx,
      'posY': st.pos.dy,
      'width': st.width,
      'height': st.height,
      'kind': st.kind.name,
      'customText': st.customText,
      'color': st.color.value,
      'rotation': st.rotation,
      ..._baseToJson(st),
    };

Map<String, dynamic> _strokeToJson(StrokeAnnotation s) => {
      'type': 'stroke',
      'id': s.id,
      'points': s.points.map((p) => [p.dx, p.dy]).toList(),
      'color': s.color.value,
      'width': s.width,
      'highlight': s.highlight,
      ..._baseToJson(s),
    };

Map<String, dynamic> _shapeToJson(ShapeAnnotation s) => {
      'type': 'shape',
      'id': s.id,
      'shapeType': s.type.name,
      'startX': s.start.dx,
      'startY': s.start.dy,
      'endX': s.end.dx,
      'endY': s.end.dy,
      'color': s.color.value,
      'width': s.width,
      'filled': s.filled,
      ..._baseToJson(s),
    };

Map<String, dynamic> _textToJson(TextAnnotation t) => {
      'type': 'text',
      'id': t.id,
      'posX': t.pos.dx,
      'posY': t.pos.dy,
      'text': t.text,
      'color': t.color.value,
      'size': t.size,
      'bold': t.bold,
      'italic': t.italic,
      'underline': t.underline,
      'fontFamily': t.fontFamily,
      'textAlign': t.textAlign.name,
      'textDirection': t.textDirection?.name,
      'lineHeight': t.lineHeight,
      'charSpacing': t.charSpacing,
      'width': t.width,
      'height': t.height,
      'rotation': t.rotation,
      ..._baseToJson(t),
    };

// ---------------------------------------------------------------------------
// Deserialize
// ---------------------------------------------------------------------------

/// Reconstruct an annotation from its JSON map. Returns null for corrupt data.
EditorAnnotation? annotationFromJson(Map<String, dynamic> j) {
  try {
    final type = j['type'] as String?;
    EditorAnnotation? a;
    switch (type) {
      case 'stroke':
        a = _strokeFromJson(j);
        break;
      case 'shape':
        a = _shapeFromJson(j);
        break;
      case 'text':
        a = _textFromJson(j);
        break;
      case 'image':
        a = _imageFromJson(j);
        break;
      case 'stamp':
        a = _stampFromJson(j);
        break;
      default:
        return null;
    }
    _applyBase(a, j);
    return a;
  } catch (_) {
    return null;
  }
}

StrokeAnnotation _strokeFromJson(Map<String, dynamic> j) {
  final points = (j['points'] as List)
      .map((p) => Offset((p[0] as num).toDouble(), (p[1] as num).toDouble()))
      .toList();
  return StrokeAnnotation(
    points,
    Color(j['color'] as int),
    (j['width'] as num).toDouble(),
    j['highlight'] as bool? ?? false,
    id: j['id'] as String?,
  );
}

ShapeAnnotation _shapeFromJson(Map<String, dynamic> j) {
  return ShapeAnnotation(
    ShapeType.values.firstWhere(
      (e) => e.name == j['shapeType'],
      orElse: () => ShapeType.rect,
    ),
    Offset((j['startX'] as num).toDouble(), (j['startY'] as num).toDouble()),
    Offset((j['endX'] as num).toDouble(), (j['endY'] as num).toDouble()),
    Color(j['color'] as int),
    (j['width'] as num).toDouble(),
    j['filled'] as bool? ?? false,
    (j['opacity'] as num?)?.toDouble() ?? 1.0,
    j['id'] as String?,
  );
}

TextAnnotation _textFromJson(Map<String, dynamic> j) {
  return TextAnnotation(
    Offset((j['posX'] as num).toDouble(), (j['posY'] as num).toDouble()),
    j['text'] as String? ?? '',
    Color(j['color'] as int? ?? Colors.black.value),
    (j['size'] as num).toDouble(),
    j['bold'] as bool? ?? false,
    italic: j['italic'] as bool? ?? false,
    underline: j['underline'] as bool? ?? false,
    fontFamily: j['fontFamily'] as String?,
    textAlign: TextAlign.values.firstWhere(
      (e) => e.name == (j['textAlign'] as String? ?? 'left'),
      orElse: () => TextAlign.left,
    ),
    textDirection: j['textDirection'] == null
        ? null
        : TextDirection.values.firstWhere(
            (e) => e.name == j['textDirection'],
            orElse: () => TextDirection.ltr,
          ),
    lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? 1.0,
    charSpacing: (j['charSpacing'] as num?)?.toDouble() ?? 0.0,
    width: (j['width'] as num?)?.toDouble(),
    height: (j['height'] as num?)?.toDouble(),
    rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
    id: j['id'] as String?,
  );
}

ImageAnnotation _imageFromJson(Map<String, dynamic> j) {
  return ImageAnnotation(
    pos: Offset((j['posX'] as num).toDouble(), (j['posY'] as num).toDouble()),
    width: (j['width'] as num).toDouble(),
    height: (j['height'] as num).toDouble(),
    bytes: base64Decode(j['bytes'] as String),
    rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
    label: j['label'] as String? ?? 'Image',
    id: j['id'] as String?,
  );
}

StampAnnotation _stampFromJson(Map<String, dynamic> j) {
  return StampAnnotation(
    pos: Offset((j['posX'] as num).toDouble(), (j['posY'] as num).toDouble()),
    width: (j['width'] as num).toDouble(),
    height: (j['height'] as num).toDouble(),
    kind: StampKind.values.firstWhere(
      (e) => e.name == j['kind'],
      orElse: () => StampKind.custom,
    ),
    customText: j['customText'] as String? ?? '',
    color: Color(j['color'] as int? ?? 0xFF000000),
    rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
    id: j['id'] as String?,
  );
}

// ---------------------------------------------------------------------------
// Layer serialization
// ---------------------------------------------------------------------------

/// Serialize all pages' annotations into a JSON-compatible map.
Map<String, dynamic> layersToJson(Map<int, PageLayer> layers) {
  final pages = <String, dynamic>{};
  for (final entry in layers.entries) {
    if (entry.value.items.isEmpty) continue;
    pages[entry.key.toString()] =
        entry.value.items.map(annotationToJson).toList();
  }
  return {
    'version': 1,
    'pages': pages,
  };
}

/// Restore annotation layers from a saved JSON map. Gracefully skips corrupt entries.
Map<int, PageLayer> layersFromJson(Map<String, dynamic> json) {
  if ((json['version'] as int? ?? 0) != 1) return {};
  final pages = json['pages'] as Map<String, dynamic>? ?? {};
  final result = <int, PageLayer>{};
  for (final entry in pages.entries) {
    final pageIndex = int.tryParse(entry.key);
    if (pageIndex == null) continue;
    final items = entry.value as List<dynamic>? ?? [];
    final layer = PageLayer();
    for (final item in items) {
      if (item is Map<String, dynamic>) {
        final annotation = annotationFromJson(item);
        if (annotation != null) {
          layer.items.add(annotation);
        }
      }
    }
    if (layer.items.isNotEmpty) {
      result[pageIndex] = layer;
    }
  }
  return result;
}
