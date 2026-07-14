import 'package:flutter/material.dart';

/// Types of PDF annotations
enum AnnotationType {
  text,
  highlight,
  freehand,
  signature,
  stamp,
  shape,
  image,
}

/// A single annotation on a PDF page
class PdfAnnotation {
  final String id;
  final AnnotationType type;
  final int pageNumber;
  final Offset position;
  final Size size;
  final String? text;
  final Color color;
  final double strokeWidth;
  final List<Offset> points; // For freehand drawing
  final String? imagePath; // For signature/stamp

  PdfAnnotation({
    required this.id,
    required this.type,
    required this.pageNumber,
    required this.position,
    this.size = const Size(200, 50),
    this.text,
    this.color = Colors.black,
    this.strokeWidth = 2.0,
    this.points = const [],
    this.imagePath,
  });

  PdfAnnotation copyWith({
    Offset? position,
    Size? size,
    String? text,
    Color? color,
    double? strokeWidth,
    List<Offset>? points,
    String? imagePath,
  }) {
    return PdfAnnotation(
      id: id,
      type: type,
      pageNumber: pageNumber,
      position: position ?? this.position,
      size: size ?? this.size,
      text: text ?? this.text,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      points: points ?? this.points,
      imagePath: imagePath ?? this.imagePath,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'page': pageNumber,
    'x': position.dx,
    'y': position.dy,
    'width': size.width,
    'height': size.height,
    'text': text,
    'color': color.value,
    'strokeWidth': strokeWidth,
    'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
  };
}

/// Tool mode for the editor
enum EditorTool {
  select,
  text,
  highlight,
  freehand,
  eraser,
  signature,
  stamp,
  shape,
}
