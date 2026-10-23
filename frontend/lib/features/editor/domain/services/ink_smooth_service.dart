import 'dart:ui' show Offset;

/// Smooths a freehand polyline so finger ink looks like a pen.
///
/// Uses Chaikin's corner-cutting algorithm (two passes). The same family of
/// curve fitting Xournal++ and other open-source ink editors apply before
/// stroking: endpoints stay put, corners become round, and the stored model
/// is still a polyline the existing stroke renderer can draw and export.
class InkSmoothService {
  const InkSmoothService();

  List<Offset> smooth(List<Offset> points, {int iterations = 2}) {
    if (points.length < 3 || iterations <= 0) {
      return List<Offset>.of(points);
    }
    var current = points;
    for (var k = 0; k < iterations; k++) {
      final next = <Offset>[current.first];
      for (var i = 0; i < current.length - 1; i++) {
        final a = current[i];
        final b = current[i + 1];
        next.add(Offset(a.dx * 0.75 + b.dx * 0.25, a.dy * 0.75 + b.dy * 0.25));
        next.add(Offset(a.dx * 0.25 + b.dx * 0.75, a.dy * 0.25 + b.dy * 0.75));
      }
      next.add(current.last);
      current = next;
    }
    return current;
  }
}
