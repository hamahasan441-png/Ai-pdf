import 'package:flutter/material.dart';
import '../models/annotation.dart';

/// Canvas for freehand drawing on PDF pages
class DrawingCanvas extends StatefulWidget {
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final Function(List<Offset>) onDrawingComplete;

  const DrawingCanvas({
    super.key,
    this.color = Colors.black,
    this.strokeWidth = 2.0,
    this.isEraser = false,
    required this.onDrawingComplete,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  List<Offset> _currentPoints = [];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (details) {
        setState(() {
          _currentPoints = [details.localPosition];
        });
      },
      onPanUpdate: (details) {
        setState(() {
          _currentPoints = [..._currentPoints, details.localPosition];
        });
      },
      onPanEnd: (details) {
        widget.onDrawingComplete(_currentPoints);
        setState(() {
          _currentPoints = [];
        });
      },
      child: CustomPaint(
        painter: _DrawingPainter(
          points: _currentPoints,
          color: widget.isEraser ? Colors.white : widget.color,
          strokeWidth: widget.isEraser ? widget.strokeWidth * 3 : widget.strokeWidth,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  _DrawingPainter({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(points[0].dx, points[0].dy);

    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) {
    return oldDelegate.points.length != points.length;
  }
}

/// Renders all existing annotations on a page
class AnnotationOverlay extends StatelessWidget {
  final List<PdfAnnotation> annotations;
  final Function(String)? onAnnotationTap;

  const AnnotationOverlay({
    super.key,
    required this.annotations,
    this.onAnnotationTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: annotations.map((annotation) {
        switch (annotation.type) {
          case AnnotationType.freehand:
            return Positioned.fill(
              child: CustomPaint(
                painter: _DrawingPainter(
                  points: annotation.points,
                  color: annotation.color,
                  strokeWidth: annotation.strokeWidth,
                ),
              ),
            );
          case AnnotationType.text:
            return Positioned(
              left: annotation.position.dx,
              top: annotation.position.dy,
              child: GestureDetector(
                onTap: () => onAnnotationTap?.call(annotation.id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: annotation.color.withOpacity(0.1),
                    border: Border.all(color: annotation.color.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    annotation.text ?? '',
                    style: TextStyle(
                      color: annotation.color,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          case AnnotationType.highlight:
            return Positioned(
              left: annotation.position.dx,
              top: annotation.position.dy,
              child: Container(
                width: annotation.size.width,
                height: annotation.size.height,
                color: annotation.color.withOpacity(0.3),
              ),
            );
          case AnnotationType.signature:
          case AnnotationType.stamp:
            return Positioned(
              left: annotation.position.dx,
              top: annotation.position.dy,
              child: GestureDetector(
                onTap: () => onAnnotationTap?.call(annotation.id),
                child: Container(
                  width: annotation.size.width,
                  height: annotation.size.height,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blue.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      annotation.text ?? 'Signature',
                      style: TextStyle(
                        fontFamily: 'cursive',
                        fontSize: 18,
                        color: annotation.color,
                      ),
                    ),
                  ),
                ),
              ),
            );
          default:
            return const SizedBox.shrink();
        }
      }).toList(),
    );
  }
}
