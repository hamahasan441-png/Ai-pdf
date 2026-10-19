import 'dart:convert' show base64Decode, base64Encode;
import 'dart:ui' show Offset, Rect, TextAlign, TextDirection;

import 'package:flutter/material.dart' show Color, Colors;

import 'package:ai_pdf/features/editor/domain/entities/annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/form_field_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/image_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/page_layer.dart';
import 'package:ai_pdf/features/editor/domain/entities/stamp_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/sticky_note_annotation.dart';
import 'package:ai_pdf/features/editor/domain/entities/text_markup_annotation.dart';

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
  if (a is TextMarkupAnnotation) return _markupToJson(a);
  if (a is StickyNoteAnnotation) return _noteToJson(a);
  if (a is FormFieldAnnotation) return _fieldToJson(a);
  return {'type': 'unknown', 'id': a.id};
}

Map<String, dynamic> _fieldToJson(FormFieldAnnotation f) => {
      'type': 'field',
      'id': f.id,
      'posX': f.pos.dx,
      'posY': f.pos.dy,
      'width': f.width,
      'height': f.height,
      'kind': f.fieldKind.name,
      'label': f.label,
      'value': f.value,
      'required': f.required,
      'checked': f.checked,
      'options': f.options,
      'multiline': f.multiline,
      'borderColor': f.borderColor.toARGB32(),
      'fillColor': f.fillColor.toARGB32(),
      'fontSize': f.fontSize,
      ..._baseToJson(f),
    };

FormFieldAnnotation _fieldFromJson(Map<String, dynamic> j) => FormFieldAnnotation(
      pos: Offset((j['posX'] as num).toDouble(), (j['posY'] as num).toDouble()),
      width: (j['width'] as num).toDouble(),
      height: (j['height'] as num).toDouble(),
      fieldKind: FormFieldKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => FormFieldKind.text),
      label: j['label'] as String? ?? '',
      value: j['value'] as String? ?? '',
      required: j['required'] as bool? ?? false,
      checked: j['checked'] as bool? ?? false,
      options: [for (final o in (j['options'] as List? ?? const [])) '$o'],
      multiline: j['multiline'] as bool? ?? false,
      borderColor: Color(j['borderColor'] as int? ?? 0xFF2563EB),
      fillColor: Color(j['fillColor'] as int? ?? 0x1A2563EB),
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? 0.018,
      id: j['id'] as String?,
    );

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

Map<String, dynamic> _markupToJson(TextMarkupAnnotation m) => {
      'type': 'markup',
      'id': m.id,
      'kind': m.kind.name,
      'color': m.color.toARGB32(),
      'text': m.text,
      'rects': [
        for (final r in m.rects) [r.left, r.top, r.right, r.bottom],
      ],
      ..._baseToJson(m),
    };

Map<String, dynamic> _noteToJson(StickyNoteAnnotation n) => {
      'type': 'note',
      'id': n.id,
      'posX': n.pos.dx,
      'posY': n.pos.dy,
      'text': n.text,
      'color': n.color.name,
      'author': n.author,
      'createdAt': n.createdAt,
      ..._baseToJson(n),
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
      'color': st.color.toARGB32(),
      'rotation': st.rotation,
      ..._baseToJson(st),
    };

Map<String, dynamic> _strokeToJson(StrokeAnnotation s) => {
      'type': 'stroke',
      'id': s.id,
      'points': s.points.map((p) => [p.dx, p.dy]).toList(),
      'color': s.color.toARGB32(),
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
      'color': s.color.toARGB32(),
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
      'color': t.color.toARGB32(),
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
      if (t.runs != null) 'runs': t.runs!.map(_runToJson).toList(),
      ..._baseToJson(t),
    };

Map<String, dynamic> _runToJson(TextRun r) => {
      'text': r.text,
      if (r.bold != null) 'bold': r.bold,
      if (r.italic != null) 'italic': r.italic,
      if (r.underline != null) 'underline': r.underline,
      if (r.color != null) 'color': r.color!.toARGB32(),
      if (r.fontFamily != null) 'fontFamily': r.fontFamily,
      if (r.sizeScale != null) 'sizeScale': r.sizeScale,
    };

List<TextRun>? _runsFromJson(Map<String, dynamic> j) {
  final raw = j['runs'];
  if (raw is! List) return null;
  final out = <TextRun>[];
  for (final e in raw) {
    if (e is Map<String, dynamic>) {
      out.add(TextRun(
        e['text'] as String? ?? '',
        bold: e['bold'] as bool?,
        italic: e['italic'] as bool?,
        underline: e['underline'] as bool?,
        color: e['color'] == null ? null : Color(e['color'] as int),
        fontFamily: e['fontFamily'] as String?,
        sizeScale: (e['sizeScale'] as num?)?.toDouble(),
      ));
    }
  }
  return out.isEmpty ? null : out;
}

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
      case 'markup':
        a = _markupFromJson(j);
        break;
      case 'note':
        a = _noteFromJson(j);
        break;
      case 'field':
        a = _fieldFromJson(j);
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

TextMarkupAnnotation _markupFromJson(Map<String, dynamic> j) {
  final rects = <Rect>[];
  final raw = j['rects'];
  if (raw is List) {
    for (final e in raw) {
      if (e is List && e.length >= 4) {
        rects.add(Rect.fromLTRB(
          (e[0] as num).toDouble(),
          (e[1] as num).toDouble(),
          (e[2] as num).toDouble(),
          (e[3] as num).toDouble(),
        ));
      }
    }
  }
  return TextMarkupAnnotation(
    kind: TextMarkupKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => TextMarkupKind.highlight,
    ),
    rects: rects,
    color: Color(j['color'] as int? ?? 0xFFFFEB3B),
    text: j['text'] as String? ?? '',
    id: j['id'] as String?,
  );
}

StickyNoteAnnotation _noteFromJson(Map<String, dynamic> j) {
  final colorName = j['color'] as String? ?? 'yellow';
  return StickyNoteAnnotation(
    pos: Offset(
      (j['posX'] as num?)?.toDouble() ?? 0.1,
      (j['posY'] as num?)?.toDouble() ?? 0.1,
    ),
    text: j['text'] as String? ?? '',
    color: StickyNoteColor.values.firstWhere(
      (c) => c.name == colorName,
      orElse: () => StickyNoteColor.yellow,
    ),
    author: j['author'] as String? ?? '',
    createdAt: j['createdAt'] as String?,
    id: j['id'] as String?,
  );
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
    Color(j['color'] as int? ?? Colors.black.toARGB32()),
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
    runs: _runsFromJson(j),
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
/// Saved form-field edits: field name → String, or List<String> for a
/// multiple choice. Unknown value types are skipped.
Map<String, Object> formValuesFromJson(Object? json) => {
      if (json is Map)
        for (final e in json.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String
          else if (e.key is String && e.value is List && (e.value as List).every((v) => v is String))
            e.key as String: List<String>.from(e.value as List),
    };

Map<String, dynamic> layersToJson(
  Map<int, PageLayer> layers, {
  SavedPageStructure? structure,
  Map<String, Object> formValues = const {},
}) {
  final pages = <String, dynamic>{};
  for (final entry in layers.entries) {
    if (entry.value.items.isEmpty) continue;
    pages[entry.key.toString()] =
        entry.value.items.map(annotationToJson).toList();
  }
  return {
    'version': 1,
    'pages': pages,
    if (structure != null) 'structure': structure.toJson(),
    if (formValues.isNotEmpty) 'forms': formValues,
  };
}

/// Page order and rotations the marks were placed on.
///
/// Page keys in `pages` are positions in the edited document, not PDF page
/// numbers. After a page was deleted, inserted or duplicated they only make
/// sense together with this structure. Files written before it existed have
/// none and are read as the PDF's own order.
class SavedPageStructure {
  /// PDF page (0-based) shown at each position; -1 is an inserted blank page.
  final List<int> sources;

  /// Clockwise quarter turns per position, 1..3. Positions not listed are 0.
  final Map<int, int> quarterTurns;

  const SavedPageStructure({required this.sources, this.quarterTurns = const {}});

  Map<String, dynamic> toJson() => {
        'sources': sources,
        'turns': {
          for (final e in quarterTurns.entries)
            if (e.value % 4 != 0) e.key.toString(): e.value % 4,
        },
      };

  /// Null when [json] is missing or malformed.
  static SavedPageStructure? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawSources = json['sources'];
    if (rawSources is! List || rawSources.isEmpty) return null;
    final sources = <int>[];
    for (final v in rawSources) {
      if (v is! int || v < -1) return null;
      sources.add(v);
    }
    final turns = <int, int>{};
    final rawTurns = json['turns'];
    if (rawTurns is Map) {
      for (final e in rawTurns.entries) {
        final key = int.tryParse('${e.key}');
        final value = e.value;
        if (key == null || key < 0 || key >= sources.length || value is! int) return null;
        if (value % 4 != 0) turns[key] = value % 4;
      }
    } else if (rawTurns != null) {
      return null;
    }
    return SavedPageStructure(sources: sources, quarterTurns: turns);
  }

  /// Whether this structure can be applied to a PDF with [pdfPageCount]
  /// pages and still hold every page key in [layers].
  bool fits(int pdfPageCount, Iterable<int> layerPages) {
    if (sources.any((s) => s >= pdfPageCount)) return false;
    return layerPages.every((p) => p >= 0 && p < sources.length);
  }

  bool get isIdentity {
    if (quarterTurns.isNotEmpty) return false;
    for (var i = 0; i < sources.length; i++) {
      if (sources[i] != i) return false;
    }
    return true;
  }
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
