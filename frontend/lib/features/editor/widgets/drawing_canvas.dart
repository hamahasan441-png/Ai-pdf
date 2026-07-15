import 'package:flutter/material.dart';

class DrawingCanvas extends StatefulWidget {
  final Color color;
  final double strokeWidth;
  final bool isEraser;
  final Function(List<Offset>) onComplete;

  const DrawingCanvas({
    super.key,
    required this.color,
    required this.strokeWidth,
    required this.isEraser,
    required this.onComplete,
  });

  @override
  State<DrawingCanvas> createState() => _DrawingCanvasState();
}

class _DrawingCanvasState extends State<DrawingCanvas> {
  List<Offset> _pts = [];

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (d) => setState(() => _pts = [d.localPosition]),
      onPanUpdate: (d) => setState(() => _pts = [..._pts, d.localPosition]),
      onPanEnd: (_) { widget.onComplete(List.from(_pts)); setState(() => _pts = []); },
      child: CustomPaint(
        painter: _Painter(
          points: _pts,
          color: widget.isEraser ? Colors.white : widget.color,
          width: widget.isEraser ? widget.strokeWidth * 4 : widget.strokeWidth,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _Painter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final double width;
  _Painter({required this.points, required this.color, required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint = Paint()..color = color..strokeWidth = width
      ..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < points.length; i++) path.lineTo(points[i].dx, points[i].dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _Painter old) => old.points.length != points.length;
}
