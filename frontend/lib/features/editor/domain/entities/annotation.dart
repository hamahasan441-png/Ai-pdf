import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Generates a lightweight unique ID without requiring a UUID package.
String _newId() {
  final rng = math.Random();
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = rng.nextInt(0x7FFFFFFF).toRadixString(36);
  return '$ts-$rand';
}

/// Shape kinds for the vector shape tools.
enum ShapeType { line, arrow, rect, oval, whiteout }

/// Base type for anything drawn on a page.
/// Every subclass carries a stable [id] so undo/redo, selection, and
/// clipboard operations can find the correct instance without relying on
/// object-identity comparisons that break after clone operations.
abstract class EditorAnnotation {
  final String id;
  EditorAnnotation({String? id}) : id = id ?? _newId();
}

/// A freehand stroke or highlight (normalised 0..1 coordinates).
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
  });
}

/// A straight line, arrow, rectangle, oval, or whiteout box.
class ShapeAnnotation extends EditorAnnotation {
  final ShapeType type;
  Offset start;
  Offset end;
  Color color;
  double width;
  bool filled;
  double opacity;

  ShapeAnnotation(
    this.type,
    this.start,
    this.end,
    this.color,
    this.width, [
    this.filled = false,
    this.opacity = 1.0,
    String? id,
  ]) : super(id: id);
}

/// A text box annotation.
///
/// Font size ([size]) is stored in **PDF points** (pt), not as a normalised
/// fraction. Use a `ptToCanvas(pt, canvasSize)` helper for on-screen rendering.
/// This matches how PDF viewers store and export text, avoiding the scaling
/// errors that occur when mixing normalised and absolute coordinate systems.
///
/// Additional fields support RTL languages (Arabic, Kurdish, Persian),
/// multi-line paragraphs, rotation, and future alignment/justification:
/// - [textAlign]   — left / center / right / justify
/// - [textDirection] — set explicitly for RTL scripts; null = auto-detect
/// - [lineHeight]  — line height multiplier (1.0 = normal, 1.5 = 150 %)
/// - [charSpacing] — extra spacing between glyphs (PDF Tc operator equivalent)
/// - [width]       — optional fixed-width bounding box in pt (null = auto)
/// - [height]      — optional fixed-height bounding box in pt (null = auto)
/// - [rotation]    — rotation in radians (0 = upright)
class TextAnnotation extends EditorAnnotation {
  /// Top-left position in normalised 0..1 page coordinates.
  Offset pos;

  String text;
  Color color;

  /// Font size in PDF points (pt). Typical range 6–144 pt.
  double size;

  bool bold;
  bool italic;
  bool underline;

  /// null = default sans-serif. Use font family names that match assets
  /// declared in pubspec.yaml (e.g. 'NotoSansArabic', 'NotoNaskhArabic',
  /// 'Vazirmatn' for Arabic/Kurdish/Persian; 'serif'; 'monospace').
  String? fontFamily;

  TextAlign textAlign;

  /// Explicit direction override. Leave null to rely on Unicode BiDi.
  /// Set to [TextDirection.rtl] for Arabic, Kurdish (Sorani/Kurmanji), Persian.
  TextDirection? textDirection;

  /// Line height multiplier. 1.0 = single-spaced.
  double lineHeight;

  /// Extra inter-character spacing in pt (equivalent to PDF Tc operator).
  double charSpacing;

  /// Bounding box width in pt. null = unconstrained (single-line auto-width).
  double? width;

  /// Bounding box height in pt. null = auto (grows with content).
  double? height;

  /// Rotation in radians. 0 = upright. Positive = counter-clockwise.
  double rotation;

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
    this.lineHeight = 1.0,
    this.charSpacing = 0.0,
    this.width,
    this.height,
    this.rotation = 0.0,
    super.id,
  });
}
