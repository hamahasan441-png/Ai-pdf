import 'dart:ui';

enum AnnotationType { text, highlight, freehand, signature, stamp, shape }
enum EditorTool { select, text, highlight, draw, eraser, sign, stamp, shapes }

class PdfAnnotation {
  final String id;
  final AnnotationType type;
  final int page;
  final Offset position;
  final Size size;
  final String? text;
  final Color color;
  final double strokeWidth;
  final List<Offset> points;

  PdfAnnotation({
    required this.id,
    required this.type,
    required this.page,
    required this.position,
    this.size = const Size(200, 50),
    this.text,
    this.color = const Color(0xFF000000),
    this.strokeWidth = 2.0,
    this.points = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id, 'type': type.name, 'page': page,
    'x': position.dx, 'y': position.dy,
    'w': size.width, 'h': size.height,
    'text': text, 'color': color.value,
    'stroke': strokeWidth,
    'points': points.map((p) => [p.dx, p.dy]).toList(),
  };
}
