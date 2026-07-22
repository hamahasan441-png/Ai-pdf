import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Compute an object's rotation (radians) from a rotate-handle drag.
///
/// [center] and [pointer] are in the same (canvas pixel) space. The result
/// matches the renderers' `canvas.rotate(-rotation)` convention: 0 = the handle
/// pointing straight up, and dragging the handle clockwise rotates the object
/// clockwise. Kept as a pure function so it is unit-testable without any widget
/// or localization dependencies.
double rotationForHandle(Offset center, Offset pointer) {
  final a = math.atan2(pointer.dy - center.dy, pointer.dx - center.dx);
  return -(a + math.pi / 2);
}
