import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Pure-Dart, CPU-bound image operations designed to run OFF the UI thread via
/// `compute()`.
///
/// Everything here is deliberately isolate-safe: inputs and outputs are only
/// [Uint8List] + primitives + a plain enum, so an [ImageOp] can be copied to a
/// background isolate and the resulting bytes copied back. No Flutter, no
/// plugins, no platform channels — so it must NOT do PDF rendering (that stays
/// on the main isolate because pdfx uses native PdfRenderer).
///
/// The logic mirrors exactly what OfflinePdfService used to do inline; only the
/// execution thread changes.

/// A special sentinel returned when an image could not be decoded and the
/// caller asked to skip (rather than throw). Callers check `result.isEmpty`.
final Uint8List _kUndecodable = Uint8List(0);

enum ImageOpType {
  /// Decode, optionally resize to [maxWidth], encode JPEG at [quality].
  /// Throws if the image cannot be decoded.
  jpegCompress,

  /// Decode and re-encode JPEG at [quality]. Falls back to the ORIGINAL bytes
  /// if the image cannot be decoded.
  jpegReencode,

  /// Decode; if either edge exceeds [maxEdge], downscale by the long edge and
  /// re-encode JPEG at [quality]. Otherwise return the original bytes unchanged.
  jpegDownscaleLongEdge,

  /// Decode; if either edge exceeds [maxEdge], downscale by the long edge and
  /// re-encode PNG (preserving alpha). Otherwise return the original bytes.
  pngDownscaleLongEdge,

  /// Decode, rotate by [degrees] (90/180/270), encode JPEG at [quality].
  /// Returns an EMPTY list if the image cannot be decoded (caller skips).
  jpegRotate,
}

/// Immutable, isolate-sendable description of one image operation.
class ImageOp {
  final ImageOpType type;
  final Uint8List bytes;
  final int quality;
  final int? maxWidth;
  final int? maxEdge;
  final int degrees;

  const ImageOp({
    required this.type,
    required this.bytes,
    this.quality = 85,
    this.maxWidth,
    this.maxEdge,
    this.degrees = 90,
  });
}

/// Top-level entry point suitable for `compute(applyImageOp, op)`.
Uint8List applyImageOp(ImageOp op) {
  switch (op.type) {
    case ImageOpType.jpegCompress:
      return _jpegCompress(op);
    case ImageOpType.jpegReencode:
      return _jpegReencode(op);
    case ImageOpType.jpegDownscaleLongEdge:
      return _jpegDownscaleLongEdge(op);
    case ImageOpType.pngDownscaleLongEdge:
      return _pngDownscaleLongEdge(op);
    case ImageOpType.jpegRotate:
      return _jpegRotate(op);
  }
}

/// True when [applyImageOp] returned the "could not decode" sentinel.
bool isUndecodable(Uint8List result) => result.isEmpty;

Uint8List _jpegCompress(ImageOp op) {
  var decoded = img.decodeImage(op.bytes);
  if (decoded == null) {
    throw Exception('Could not decode image');
  }
  final maxWidth = op.maxWidth;
  if (maxWidth != null && decoded.width > maxWidth) {
    decoded = img.copyResize(decoded, width: maxWidth);
  }
  return Uint8List.fromList(img.encodeJpg(decoded, quality: op.quality));
}

Uint8List _jpegReencode(ImageOp op) {
  final decoded = img.decodeImage(op.bytes);
  if (decoded == null) return op.bytes;
  return Uint8List.fromList(img.encodeJpg(decoded, quality: op.quality));
}

Uint8List _jpegDownscaleLongEdge(ImageOp op) {
  final maxEdge = op.maxEdge;
  final decoded = img.decodeImage(op.bytes);
  if (decoded == null || maxEdge == null) return op.bytes;
  if (decoded.width > maxEdge || decoded.height > maxEdge) {
    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxEdge)
        : img.copyResize(decoded, height: maxEdge);
    return Uint8List.fromList(img.encodeJpg(resized, quality: op.quality));
  }
  return op.bytes;
}

Uint8List _pngDownscaleLongEdge(ImageOp op) {
  final maxEdge = op.maxEdge;
  final decoded = img.decodeImage(op.bytes);
  if (decoded == null || maxEdge == null) return op.bytes;
  if (decoded.width > maxEdge || decoded.height > maxEdge) {
    final resized = decoded.width >= decoded.height
        ? img.copyResize(decoded, width: maxEdge)
        : img.copyResize(decoded, height: maxEdge);
    return Uint8List.fromList(img.encodePng(resized));
  }
  return op.bytes;
}

Uint8List _jpegRotate(ImageOp op) {
  final decoded = img.decodeImage(op.bytes);
  if (decoded == null) return _kUndecodable;
  final angle = (op.degrees ~/ 90).clamp(1, 3); // 1=90, 2=180, 3=270
  final rotated = angle == 1
      ? img.copyRotate(decoded, angle: 90)
      : angle == 2
          ? img.copyRotate(decoded, angle: 180)
          : img.copyRotate(decoded, angle: 270);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: op.quality));
}
