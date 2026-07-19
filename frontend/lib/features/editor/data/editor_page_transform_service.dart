import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:math' as math;

/// Image-space transforms for already-rendered editor pages.
class EditorPageTransformService {
  const EditorPageTransformService();

  /// Rotate a rendered page image 90° clockwise and return the transformed bytes.
  Future<Uint8List?> rotateClockwise(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final original = frame.image;
    final w = original.height;
    final h = original.width;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    canvas.translate(w.toDouble(), 0);
    canvas.rotate(math.pi / 2);
    canvas.drawImage(original, ui.Offset.zero, ui.Paint());
    original.dispose();
    final picture = recorder.endRecording();
    final rotated = await picture.toImage(w, h);
    try {
      final data = await rotated.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      rotated.dispose();
      picture.dispose();
    }
  }
}
