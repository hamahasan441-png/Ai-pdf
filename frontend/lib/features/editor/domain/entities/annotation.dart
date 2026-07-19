import 'package:flutter/material.dart';

/// Shape kinds for the vector shape tools.
enum ShapeType { line, arrow, rect, oval, whiteout }

/// Base type for anything drawn on a page (used for undo/redo ordering).
abstract class EditorAnnotation {}

/// A freehand stroke or highlight (normalized 0..1 coordinates).
class StrokeAnnotation extends EditorAnnotation {
  final List<Offset> points;
  final Color color;
  final double width;
  final bool highlight;

  StrokeAnnotation(this.points, this.color, this.width, this.highlight);
}

/// A straight line, arrow, rectangle, oval, or whiteout box (normalized coordinates).
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
  ]);
}

/// A text box annotation (normalized position).
class TextAnnotation extends EditorAnnotation {
  Offset pos;
  String text;
  Color color;
  double size; // normalized to canvas height
  bool bold;
  bool italic;
  bool underline;
  String? fontFamily; // null = default, 'serif', 'monospace'

  TextAnnotation(
    this.pos,
    this.text,
    this.color,
    this.size,
    this.bold, [
    this.italic = false,
    this.underline = false,
    this.fontFamily,
  ]);
}
