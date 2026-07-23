import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Generates a lightweight unique ID without requiring a UUID package.
String _newId() {
  final rng = math.Random();
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final rand = rng.nextInt(0x7FFFFFFF).toRadixString(36);
  return '$ts-$rand';
}

/// Clamp a normalised offset into the [0, max] page range on both axes.
Offset clampOffset01(Offset o, [double max = 1.0]) =>
    Offset(o.dx.clamp(0.0, max), o.dy.clamp(0.0, max));

/// Shape kinds for the vector shape tools.
enum ShapeType { line, arrow, rect, oval, whiteout }

/// Base type for anything drawn on a page — the editor's unified Document
/// Object Model (DOM) node.
///
/// Every object, regardless of kind, is [Transformable]: it exposes a
/// normalised bounding box and can be translated, scaled, cloned, and restored
/// from a snapshot. This lets the selection engine, history engine, and
/// clipboard treat every object uniformly and lets new object types be added
/// without touching those subsystems.
///
/// ### Shared presentation state
/// - [opacity]   — 0..1 alpha applied to the whole object (1 = opaque).
/// - [locked]    — when true the object should not be moved/edited by gestures.
/// - [visible]   — when false the object is hidden (kept in the model/export).
/// - [zIndex]    — advisory paint order hint (list order remains authoritative).
/// - [metadata]  — free-form bag for future features (AI provenance, links…).
///
/// Every subclass carries a stable [id] so undo/redo, selection, and clipboard
/// operations can find the correct instance without relying on object-identity
/// comparisons that break after clone operations.
abstract class EditorAnnotation {
  final String id;

  double opacity;
  bool locked;
  bool visible;
  int zIndex;
  Map<String, dynamic> metadata;

  EditorAnnotation({
    String? id,
    this.opacity = 1.0,
    this.locked = false,
    this.visible = true,
    this.zIndex = 0,
    Map<String, dynamic>? metadata,
  })  : id = id ?? _newId(),
        metadata = metadata ?? <String, dynamic>{};

  // ── Transformable contract ────────────────────────────────────────────

  /// Normalised (0..1) axis-aligned bounding box on the page.
  Rect get bounds;

  /// Translate the object by a normalised [delta] (clamped to the page).
  void translate(Offset delta);

  /// Resize the object so its bounding box becomes [next] (normalised).
  void scaleTo(Rect next);

  /// Deep copy this object. [shift] offsets the copy diagonally (normalised);
  /// [id] lets callers preserve the id (for history snapshots) — omit it to
  /// mint a fresh id (for duplicate / paste).
  EditorAnnotation clone({double shift = 0, String? id});

  /// Restore this object's mutable state from [other] (a snapshot of the same
  /// runtime type). Used by the history engine to undo/redo in place, keeping
  /// existing references (selection, inline editor) valid.
  void restoreFrom(covariant EditorAnnotation other);

  /// Copy the shared presentation state from [o]. Subclasses call this from
  /// their [clone] and [restoreFrom] implementations.
  void copyBaseFrom(EditorAnnotation o) {
    opacity = o.opacity;
    locked = o.locked;
    visible = o.visible;
    zIndex = o.zIndex;
    metadata = Map<String, dynamic>.of(o.metadata);
  }
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

  @override
  Rect get bounds {
    if (points.isEmpty) return Rect.zero;
    var minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  @override
  void translate(Offset delta) {
    for (var i = 0; i < points.length; i++) {
      points[i] = clampOffset01(points[i] + delta);
    }
  }

  @override
  void scaleTo(Rect next) {
    final old = bounds;
    final ow = old.width.abs() < 1e-6 ? 1e-6 : old.width;
    final oh = old.height.abs() < 1e-6 ? 1e-6 : old.height;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      points[i] = Offset(
        (next.left + (p.dx - old.left) / ow * next.width).clamp(0.0, 1.0),
        (next.top + (p.dy - old.top) / oh * next.height).clamp(0.0, 1.0),
      );
    }
  }

  @override
  StrokeAnnotation clone({double shift = 0, String? id}) {
    final c = StrokeAnnotation(
      points.map((p) => Offset(p.dx + shift, p.dy + shift)).toList(),
      color,
      width,
      highlight,
      id: id,
    );
    c.copyBaseFrom(this);
    return c;
  }

  @override
  void restoreFrom(StrokeAnnotation o) {
    points
      ..clear()
      ..addAll(o.points.map((p) => Offset(p.dx, p.dy)));
    copyBaseFrom(o);
  }
}

/// A straight line, arrow, rectangle, oval, or whiteout box.
class ShapeAnnotation extends EditorAnnotation {
  final ShapeType type;
  Offset start;
  Offset end;
  Color color;
  double width;
  bool filled;

  ShapeAnnotation(
    this.type,
    this.start,
    this.end,
    this.color,
    this.width, [
    this.filled = false,
    double opacity = 1.0,
    String? id,
  ]) : super(id: id, opacity: opacity);

  @override
  Rect get bounds => Rect.fromPoints(start, end);

  @override
  void translate(Offset delta) {
    start = clampOffset01(start + delta);
    end = clampOffset01(end + delta);
  }

  @override
  void scaleTo(Rect next) {
    final old = bounds;
    final ow = old.width.abs() < 1e-6 ? 1e-6 : old.width;
    final oh = old.height.abs() < 1e-6 ? 1e-6 : old.height;
    double mapX(double x) => next.left + (x - old.left) / ow * next.width;
    double mapY(double y) => next.top + (y - old.top) / oh * next.height;
    start = Offset(mapX(start.dx).clamp(0.0, 1.0), mapY(start.dy).clamp(0.0, 1.0));
    end = Offset(mapX(end.dx).clamp(0.0, 1.0), mapY(end.dy).clamp(0.0, 1.0));
  }

  @override
  ShapeAnnotation clone({double shift = 0, String? id}) {
    final c = ShapeAnnotation(
      type,
      Offset(start.dx + shift, start.dy + shift),
      Offset(end.dx + shift, end.dy + shift),
      color,
      width,
      filled,
      opacity,
      id,
    );
    c.copyBaseFrom(this);
    return c;
  }

  @override
  void restoreFrom(ShapeAnnotation o) {
    start = o.start;
    end = o.end;
    color = o.color;
    width = o.width;
    filled = o.filled;
    copyBaseFrom(o);
  }
}

/// A single styled run within a rich-text [TextAnnotation].
///
/// Each override is nullable: a null field means "inherit the annotation's
/// base style" so a run only needs to specify what differs. [sizeScale] is a
/// multiplier applied to the base font size (1.0 = same size).
class TextRun {
  final String text;
  final bool? bold;
  final bool? italic;
  final bool? underline;
  final Color? color;
  final String? fontFamily;
  final double? sizeScale;

  const TextRun(
    this.text, {
    this.bold,
    this.italic,
    this.underline,
    this.color,
    this.fontFamily,
    this.sizeScale,
  });
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

  /// Optional rich-text runs. When null/empty the whole box uses the base
  /// style above (the common case). When present, the runs define per-span
  /// styling and their concatenation should equal [text].
  List<TextRun>? runs;

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
    this.runs,
    super.id,
  });

  @override
  Rect get bounds {
    // Estimate width: non-Latin (Arabic/Hebrew/CJK) chars are wider than Latin.
    final avgCharWidth = _hasWideChars(text) ? 0.7 : 0.55;
    final w = (text.length * size * avgCharWidth).clamp(0.02, 1.0);
    return Rect.fromLTWH(pos.dx, pos.dy, w.toDouble(), size * 1.3);
  }

  static bool _hasWideChars(String text) {
    for (final cp in text.runes) {
      if ((cp >= 0x0600 && cp <= 0x06FF) || // Arabic
          (cp >= 0x0590 && cp <= 0x05FF) || // Hebrew
          (cp >= 0x4E00 && cp <= 0x9FFF) || // CJK
          (cp >= 0xFB50 && cp <= 0xFDFF)) return true;
    }
    return false;
  }

  @override
  void translate(Offset delta) {
    pos = clampOffset01(pos + delta, 0.98);
  }

  @override
  void scaleTo(Rect next) {
    final old = bounds;
    final oh = old.height.abs() < 1e-6 ? 1e-6 : old.height;
    pos = Offset(next.left.clamp(0.0, 0.98), next.top.clamp(0.0, 0.98));
    size = (size * (next.height / oh)).clamp(0.01, 0.2);
  }

  @override
  TextAnnotation clone({double shift = 0, String? id}) {
    final c = TextAnnotation(
      Offset(pos.dx + shift, pos.dy + shift),
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
      runs: runs == null ? null : List<TextRun>.of(runs!),
      id: id,
    );
    c.copyBaseFrom(this);
    return c;
  }

  @override
  void restoreFrom(TextAnnotation o) {
    pos = o.pos;
    text = o.text;
    color = o.color;
    size = o.size;
    bold = o.bold;
    italic = o.italic;
    underline = o.underline;
    fontFamily = o.fontFamily;
    textAlign = o.textAlign;
    textDirection = o.textDirection;
    lineHeight = o.lineHeight;
    charSpacing = o.charSpacing;
    width = o.width;
    height = o.height;
    rotation = o.rotation;
    runs = o.runs == null ? null : List<TextRun>.of(o.runs!);
    copyBaseFrom(o);
  }
}
