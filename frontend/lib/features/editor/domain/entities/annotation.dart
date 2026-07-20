import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// ID generator
// ---------------------------------------------------------------------------

String _newId() {
  final rng = math.Random();
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = rng.nextInt(0x7FFFFFFF).toRadixString(36);
  return '$ts-$rand';
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Shape kinds for vector shape tools.
enum ShapeType { line, arrow, rect, oval, whiteout }

/// Every annotation carries an explicit type tag for serialisation and
/// pattern-matching without `is`-chains everywhere.
enum AnnotationType {
  stroke,
  shape,
  text,
  image,
  stamp,
  formField,
  signature,
}

/// Form field sub-types — mirrors DetectedField.FieldType.
enum FormFieldType { text, number, date, email, phone, name, signature, checkbox, radio }

/// Stamp categories.
enum StampKind { approved, rejected, confidential, draft, final_, paid, void_, custom }

// ---------------------------------------------------------------------------
// Base
// ---------------------------------------------------------------------------

/// Base class for every object on a page.
///
/// Every annotation carries:
/// - a stable [id]  (survives clone / paste / undo cycles)
/// - [zIndex]       (draw order — lower = further back)
/// - [locked]       (prevent accidental moves/edits)
/// - [visible]      (soft hide without deleting)
/// - [opacity]      (0.0 – 1.0, applied at composite time)
/// - [pageIndex]    (which page owns this — enables cross-page undo)
abstract class EditorAnnotation {
  final String id;
  final AnnotationType type;

  /// Draw order relative to other annotations on the same page.
  /// Stored so serialisation round-trips preserve layer order.
  int zIndex;

  bool locked;
  bool visible;

  /// Composite opacity applied on top of any per-stroke/fill alpha.
  double opacity;

  /// 0-based index of the page that owns this annotation.
  int pageIndex;

  EditorAnnotation({
    String? id,
    required this.type,
    this.zIndex = 0,
    this.locked = false,
    this.visible = true,
    this.opacity = 1.0,
    this.pageIndex = 0,
  }) : id = id ?? _newId();

  /// Produce a deep copy with a new ID. Used by copy/paste/duplicate.
  EditorAnnotation clone({double offsetNorm = 0.0, int? newPageIndex});

  /// Serialise to a JSON-compatible map.
  Map<String, dynamic> toJson();
}

// ---------------------------------------------------------------------------
// Stroke
// ---------------------------------------------------------------------------

/// A freehand stroke or highlight. All points are in normalised 0..1 coords.
class StrokeAnnotation extends EditorAnnotation {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool highlight;

  StrokeAnnotation(
    this.points,
    this.color,
    this.width,
    this.highlight, {
    super.id,
    super.zIndex,
    super.locked,
    super.visible,
    super.opacity,
    super.pageIndex,
  }) : super(type: AnnotationType.stroke);

  @override
  StrokeAnnotation clone({double offsetNorm = 0.0, int? newPageIndex}) {
    return StrokeAnnotation(
      points.map((p) => Offset(p.dx + offsetNorm, p.dy + offsetNorm)).toList(),
      color,
      width,
      highlight,
      zIndex: zIndex,
      opacity: opacity,
      pageIndex: newPageIndex ?? pageIndex,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'stroke',
        'zIndex': zIndex,
        'locked': locked,
        'visible': visible,
        'opacity': opacity,
        'pageIndex': pageIndex,
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'color': color.value,
        'width': width,
        'highlight': highlight,
      };

  factory StrokeAnnotation.fromJson(Map<String, dynamic> j) => StrokeAnnotation(
        (j['points'] as List)
            .map((p) => Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble()))
            .toList(),
        Color(j['color'] as int),
        (j['width'] as num).toDouble(),
        j['highlight'] as bool? ?? false,
        id: j['id'] as String?,
        zIndex: j['zIndex'] as int? ?? 0,
        locked: j['locked'] as bool? ?? false,
        visible: j['visible'] as bool? ?? true,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        pageIndex: j['pageIndex'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Shape
// ---------------------------------------------------------------------------

/// A straight line, arrow, rectangle, oval, or whiteout box.
class ShapeAnnotation extends EditorAnnotation {
  final ShapeType shape;
  Offset start;
  Offset end;
  Color color;
  double width;
  bool filled;

  ShapeAnnotation(
    this.shape,
    this.start,
    this.end,
    this.color,
    this.width, {
    this.filled = false,
    super.id,
    super.zIndex,
    super.locked,
    super.visible,
    super.opacity,
    super.pageIndex,
  }) : super(type: AnnotationType.shape);

  // Legacy accessor — existing code uses `.type` to mean shape sub-kind.
  ShapeType get type => shape;

  @override
  ShapeAnnotation clone({double offsetNorm = 0.0, int? newPageIndex}) {
    return ShapeAnnotation(
      shape,
      Offset(start.dx + offsetNorm, start.dy + offsetNorm),
      Offset(end.dx + offsetNorm, end.dy + offsetNorm),
      color,
      width,
      filled: filled,
      zIndex: zIndex,
      opacity: opacity,
      pageIndex: newPageIndex ?? pageIndex,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'shape',
        'shape': shape.name,
        'zIndex': zIndex,
        'locked': locked,
        'visible': visible,
        'opacity': opacity,
        'pageIndex': pageIndex,
        'startX': start.dx,
        'startY': start.dy,
        'endX': end.dx,
        'endY': end.dy,
        'color': color.value,
        'width': width,
        'filled': filled,
      };

  factory ShapeAnnotation.fromJson(Map<String, dynamic> j) => ShapeAnnotation(
        ShapeType.values.firstWhere((e) => e.name == j['shape'], orElse: () => ShapeType.rect),
        Offset((j['startX'] as num).toDouble(), (j['startY'] as num).toDouble()),
        Offset((j['endX'] as num).toDouble(), (j['endY'] as num).toDouble()),
        Color(j['color'] as int),
        (j['width'] as num).toDouble(),
        filled: j['filled'] as bool? ?? false,
        id: j['id'] as String?,
        zIndex: j['zIndex'] as int? ?? 0,
        locked: j['locked'] as bool? ?? false,
        visible: j['visible'] as bool? ?? true,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        pageIndex: j['pageIndex'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

/// A professional text box annotation.
///
/// ### Coordinate system
/// [pos] is the **top-left corner** in normalised 0..1 page coordinates.
/// [size] is the font size in **PDF points (pt)** — stored absolute so export
/// is pixel-perfect regardless of on-screen canvas size.
/// Use `ptToNorm(pt, canvasHeight)` / `normToPt(norm, canvasHeight)` to
/// convert between the two systems.
///
/// ### RTL / complex-script support
/// [textDirection] can be set to [TextDirection.rtl] for Arabic, Kurdish,
/// Persian, Hebrew, Urdu. When null the renderer uses Unicode auto-BiDi.
/// [fontFamily] should be a Noto or Vazirmatn family for correct shaping;
/// export embeds the font so the PDF renders correctly on any viewer.
///
/// ### Layout engine fields
/// [lineHeight]  — multiplier (1.0 = normal, 1.5 = 150 %)
/// [charSpacing] — extra pt between glyphs (PDF Tc operator)
/// [width]       — bounding box width in pt  (null = auto)
/// [height]      — bounding box height in pt (null = auto)
/// [rotation]    — radians; positive = counter-clockwise
class TextAnnotation extends EditorAnnotation {
  Offset pos;
  String text;
  Color color;

  /// Font size in PDF points.
  double size;

  bool bold;
  bool italic;
  bool underline;
  String? fontFamily;
  TextAlign textAlign;
  TextDirection? textDirection;
  double lineHeight;
  double charSpacing;
  double? width;
  double? height;
  double rotation;

  /// Background fill color for the text box (null = transparent).
  Color? backgroundColor;

  /// Border color drawn around the text box (null = no border).
  Color? borderColor;
  double borderWidth;

  TextAnnotation(
    this.pos,
    this.text,
    this.color,
    this.size,
    this.bold, {
    this.italic = false,
    this.underline = false,
    this.fontFamily,
    this.textAlign = TextAlign.left,
    this.textDirection,
    this.lineHeight = 1.2,
    this.charSpacing = 0.0,
    this.width,
    this.height,
    this.rotation = 0.0,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    super.id,
    super.zIndex,
    super.locked,
    super.visible,
    super.opacity,
    super.pageIndex,
  }) : super(type: AnnotationType.text);

  /// Convert a normalised font-size fraction to pt given canvas height.
  static double normToPt(double norm, double canvasHeight) => norm * canvasHeight;

  /// Convert a pt font size to normalised fraction given canvas height.
  static double ptToNorm(double pt, double canvasHeight) =>
      canvasHeight > 0 ? pt / canvasHeight : 0.02;

  @override
  TextAnnotation clone({double offsetNorm = 0.0, int? newPageIndex}) {
    return TextAnnotation(
      Offset(pos.dx + offsetNorm, pos.dy + offsetNorm),
      text,
      color,
      size,
      bold,
      italic: italic,
      underline: underline,
      fontFamily: fontFamily,
      textAlign: textAlign,
      textDirection: textDirection,
      lineHeight: lineHeight,
      charSpacing: charSpacing,
      width: width,
      height: height,
      rotation: rotation,
      backgroundColor: backgroundColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      zIndex: zIndex,
      opacity: opacity,
      pageIndex: newPageIndex ?? pageIndex,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'text',
        'zIndex': zIndex,
        'locked': locked,
        'visible': visible,
        'opacity': opacity,
        'pageIndex': pageIndex,
        'posX': pos.dx,
        'posY': pos.dy,
        'text': text,
        'color': color.value,
        'size': size,
        'bold': bold,
        'italic': italic,
        'underline': underline,
        'fontFamily': fontFamily,
        'textAlign': textAlign.name,
        'textDirection': textDirection?.name,
        'lineHeight': lineHeight,
        'charSpacing': charSpacing,
        'width': width,
        'height': height,
        'rotation': rotation,
        'backgroundColor': backgroundColor?.value,
        'borderColor': borderColor?.value,
        'borderWidth': borderWidth,
      };

  factory TextAnnotation.fromJson(Map<String, dynamic> j) {
    final tdStr = j['textDirection'] as String?;
    final taStr = j['textAlign'] as String? ?? 'left';
    return TextAnnotation(
      Offset((j['posX'] as num).toDouble(), (j['posY'] as num).toDouble()),
      j['text'] as String? ?? '',
      Color(j['color'] as int),
      (j['size'] as num).toDouble(),
      j['bold'] as bool? ?? false,
      italic: j['italic'] as bool? ?? false,
      underline: j['underline'] as bool? ?? false,
      fontFamily: j['fontFamily'] as String?,
      textAlign: TextAlign.values.firstWhere((e) => e.name == taStr, orElse: () => TextAlign.left),
      textDirection: tdStr == null
          ? null
          : TextDirection.values.firstWhere((e) => e.name == tdStr, orElse: () => TextDirection.ltr),
      lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? 1.2,
      charSpacing: (j['charSpacing'] as num?)?.toDouble() ?? 0.0,
      width: (j['width'] as num?)?.toDouble(),
      height: (j['height'] as num?)?.toDouble(),
      rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
      backgroundColor: j['backgroundColor'] != null ? Color(j['backgroundColor'] as int) : null,
      borderColor: j['borderColor'] != null ? Color(j['borderColor'] as int) : null,
      borderWidth: (j['borderWidth'] as num?)?.toDouble() ?? 1.0,
      id: j['id'] as String?,
      zIndex: j['zIndex'] as int? ?? 0,
      locked: j['locked'] as bool? ?? false,
      visible: j['visible'] as bool? ?? true,
      opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
      pageIndex: j['pageIndex'] as int? ?? 0,
    );
  }
}

// ---------------------------------------------------------------------------
// Image
// ---------------------------------------------------------------------------

/// A raster image overlay (photo, scanned stamp, etc.).
class ImageAnnotation extends EditorAnnotation {
  /// Normalised bounding box.
  Offset pos;
  double width;
  double height;

  /// The raw PNG/JPEG bytes of the image.
  Uint8List bytes;

  /// Rotation in radians.
  double rotation;

  ImageAnnotation({
    required this.pos,
    required this.width,
    required this.height,
    required this.bytes,
    this.rotation = 0.0,
    super.id,
    super.zIndex,
    super.locked,
    super.visible,
    super.opacity,
    super.pageIndex,
  }) : super(type: AnnotationType.image);

  @override
  ImageAnnotation clone({double offsetNorm = 0.0, int? newPageIndex}) {
    return ImageAnnotation(
      pos: Offset(pos.dx + offsetNorm, pos.dy + offsetNorm),
      width: width,
      height: height,
      bytes: Uint8List.fromList(bytes),
      rotation: rotation,
      zIndex: zIndex,
      opacity: opacity,
      pageIndex: newPageIndex ?? pageIndex,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'image',
        'zIndex': zIndex,
        'locked': locked,
        'visible': visible,
        'opacity': opacity,
        'pageIndex': pageIndex,
        'posX': pos.dx,
        'posY': pos.dy,
        'width': width,
        'height': height,
        // bytes serialised as base64 when persisting — handled externally
        'rotation': rotation,
      };
}

// ---------------------------------------------------------------------------
// Stamp
// ---------------------------------------------------------------------------

/// A predefined or custom text/vector stamp.
class StampAnnotation extends EditorAnnotation {
  Offset pos;
  double width;
  double height;
  StampKind kind;
  String customText;
  Color color;
  double rotation;

  StampAnnotation({
    required this.pos,
    required this.width,
    required this.height,
    required this.kind,
    this.customText = '',
    required this.color,
    this.rotation = 0.0,
    super.id,
    super.zIndex,
    super.locked,
    super.visible,
    super.opacity,
    super.pageIndex,
  }) : super(type: AnnotationType.stamp);

  String get displayText {
    switch (kind) {
      case StampKind.approved:
        return 'APPROVED';
      case StampKind.rejected:
        return 'REJECTED';
      case StampKind.confidential:
        return 'CONFIDENTIAL';
      case StampKind.draft:
        return 'DRAFT';
      case StampKind.final_:
        return 'FINAL';
      case StampKind.paid:
        return 'PAID';
      case StampKind.void_:
        return 'VOID';
      case StampKind.custom:
        return customText;
    }
  }

  @override
  StampAnnotation clone({double offsetNorm = 0.0, int? newPageIndex}) {
    return StampAnnotation(
      pos: Offset(pos.dx + offsetNorm, pos.dy + offsetNorm),
      width: width,
      height: height,
      kind: kind,
      customText: customText,
      color: color,
      rotation: rotation,
      zIndex: zIndex,
      opacity: opacity,
      pageIndex: newPageIndex ?? pageIndex,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'stamp',
        'zIndex': zIndex,
        'locked': locked,
        'visible': visible,
        'opacity': opacity,
        'pageIndex': pageIndex,
        'posX': pos.dx,
        'posY': pos.dy,
        'width': width,
        'height': height,
        'kind': kind.name,
        'customText': customText,
        'color': color.value,
        'rotation': rotation,
      };

  factory StampAnnotation.fromJson(Map<String, dynamic> j) => StampAnnotation(
        pos: Offset((j['posX'] as num).toDouble(), (j['posY'] as num).toDouble()),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        kind: StampKind.values.firstWhere((e) => e.name == j['kind'], orElse: () => StampKind.draft),
        customText: j['customText'] as String? ?? '',
        color: Color(j['color'] as int),
        rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
        id: j['id'] as String?,
        zIndex: j['zIndex'] as int? ?? 0,
        locked: j['locked'] as bool? ?? false,
        visible: j['visible'] as bool? ?? true,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        pageIndex: j['pageIndex'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Form field overlay
// ---------------------------------------------------------------------------

/// An interactive form-field overlay (for AcroForm-style fill UX).
class FormFieldAnnotation extends EditorAnnotation {
  Offset pos;
  double width;
  double height;
  FormFieldType fieldType;
  String label;
  String value;
  bool required;
  bool checked; // for checkbox / radio
  Color borderColor;
  Color fillColor;
  double fontSize;
  String? fontFamily;

  FormFieldAnnotation({
    required this.pos,
    required this.width,
    required this.height,
    required this.fieldType,
    required this.label,
    this.value = '',
    this.required = false,
    this.checked = false,
    this.borderColor = const Color(0xFF2563EB),
    this.fillColor = const Color(0x1A2563EB),
    this.fontSize = 12.0,
    this.fontFamily,
    super.id,
    super.zIndex,
    super.locked,
    super.visible,
    super.opacity,
    super.pageIndex,
  }) : super(type: AnnotationType.formField);

  bool get isCheckable => fieldType == FormFieldType.checkbox || fieldType == FormFieldType.radio;

  @override
  FormFieldAnnotation clone({double offsetNorm = 0.0, int? newPageIndex}) {
    return FormFieldAnnotation(
      pos: Offset(pos.dx + offsetNorm, pos.dy + offsetNorm),
      width: width,
      height: height,
      fieldType: fieldType,
      label: label,
      value: value,
      required: required,
      checked: checked,
      borderColor: borderColor,
      fillColor: fillColor,
      fontSize: fontSize,
      fontFamily: fontFamily,
      zIndex: zIndex,
      opacity: opacity,
      pageIndex: newPageIndex ?? pageIndex,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'formField',
        'zIndex': zIndex,
        'locked': locked,
        'visible': visible,
        'opacity': opacity,
        'pageIndex': pageIndex,
        'posX': pos.dx,
        'posY': pos.dy,
        'width': width,
        'height': height,
        'fieldType': fieldType.name,
        'label': label,
        'value': value,
        'required': required,
        'checked': checked,
        'borderColor': borderColor.value,
        'fillColor': fillColor.value,
        'fontSize': fontSize,
        'fontFamily': fontFamily,
      };

  factory FormFieldAnnotation.fromJson(Map<String, dynamic> j) => FormFieldAnnotation(
        pos: Offset((j['posX'] as num).toDouble(), (j['posY'] as num).toDouble()),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
        fieldType: FormFieldType.values
            .firstWhere((e) => e.name == j['fieldType'], orElse: () => FormFieldType.text),
        label: j['label'] as String? ?? '',
        value: j['value'] as String? ?? '',
        required: j['required'] as bool? ?? false,
        checked: j['checked'] as bool? ?? false,
        borderColor: Color(j['borderColor'] as int? ?? 0xFF2563EB),
        fillColor: Color(j['fillColor'] as int? ?? 0x1A2563EB),
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 12.0,
        fontFamily: j['fontFamily'] as String?,
        id: j['id'] as String?,
        zIndex: j['zIndex'] as int? ?? 0,
        locked: j['locked'] as bool? ?? false,
        visible: j['visible'] as bool? ?? true,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 1.0,
        pageIndex: j['pageIndex'] as int? ?? 0,
      );
}

// ---------------------------------------------------------------------------
// Deserialisation factory
// ---------------------------------------------------------------------------

/// Reconstruct any annotation from its JSON map.
EditorAnnotation annotationFromJson(Map<String, dynamic> j) {
  final t = j['type'] as String? ?? '';
  switch (t) {
    case 'stroke':
      return StrokeAnnotation.fromJson(j);
    case 'shape':
      return ShapeAnnotation.fromJson(j);
    case 'text':
      return TextAnnotation.fromJson(j);
    case 'stamp':
      return StampAnnotation.fromJson(j);
    case 'formField':
      return FormFieldAnnotation.fromJson(j);
    default:
      // Fallback — treat as an empty shape so nothing crashes.
      return ShapeAnnotation(
        ShapeType.rect,
        Offset.zero,
        Offset.zero,
        Colors.transparent,
        0,
      );
  }
}
