import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

/// Isolate-safe image operations.
///
/// ### Design principle
/// Every function here is a top-level function (or static) so it can be
/// passed to [compute] / [Isolate.run]. They accept and return only simple
/// types (Uint8List, int, double) — no Flutter framework objects.
///
/// This keeps the UI thread free for animations and touch events while
/// expensive image work happens in a background isolate.

// ---------------------------------------------------------------------------
// Synchronous single-op API (used by isolate entry points & tests)
// ---------------------------------------------------------------------------

/// The type of image operation to perform.
enum ImageOpType {
  jpegReencode,
  jpegRotate,
  jpegDownscaleLongEdge,
  pngDownscaleLongEdge,
  jpegCompress,
}

/// A value object describing a single image transformation.
class ImageOp {
  final ImageOpType type;
  final Uint8List bytes;
  final int? quality;
  final int? degrees;
  final int? maxEdge;

  const ImageOp({
    required this.type,
    required this.bytes,
    this.quality,
    this.degrees,
    this.maxEdge,
  });
}

/// Sentinel: an empty [Uint8List] signals that decoding failed and the caller
/// should skip this operation rather than using corrupt output.
final Uint8List _undecodableSentinel = Uint8List(0);

/// Returns `true` if [bytes] is the undecodable sentinel (empty list returned
/// by operations that cannot decode their input and want the caller to skip).
bool isUndecodable(Uint8List bytes) => bytes.isEmpty;

/// Apply a single synchronous image operation.
///
/// This is the workhorse called inside isolates. It handles undecodable input
/// gracefully per operation type:
/// - [ImageOpType.jpegReencode]: returns original bytes (no-op fallback)
/// - [ImageOpType.jpegRotate]: returns empty sentinel (caller skips)
/// - [ImageOpType.jpegDownscaleLongEdge]: returns original if maxEdge is null
/// - [ImageOpType.pngDownscaleLongEdge]: returns original if cannot decode
/// - [ImageOpType.jpegCompress]: throws (surfaced to the user as an error)
Uint8List applyImageOp(ImageOp op) {
  switch (op.type) {
    case ImageOpType.jpegReencode:
      final decoded = img.decodeImage(op.bytes);
      if (decoded == null) return op.bytes; // fallback: return original
      return Uint8List.fromList(
          img.encodeJpg(decoded, quality: op.quality ?? 85));

    case ImageOpType.jpegRotate:
      final decoded = img.decodeImage(op.bytes);
      if (decoded == null) return _undecodableSentinel; // sentinel
      final degrees = op.degrees ?? 0;
      final rotated = img.copyRotate(decoded, angle: degrees.toDouble());
      return Uint8List.fromList(
          img.encodeJpg(rotated, quality: op.quality ?? 90));

    case ImageOpType.jpegDownscaleLongEdge:
      if (op.maxEdge == null) return op.bytes;
      final decoded = img.decodeImage(op.bytes);
      if (decoded == null) return op.bytes;
      final longEdge =
          decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longEdge <= op.maxEdge!) return op.bytes;
      final scaled = img.copyResize(
        decoded,
        width: decoded.width > decoded.height ? op.maxEdge : null,
        height: decoded.height >= decoded.width ? op.maxEdge : null,
        interpolation: img.Interpolation.linear,
      );
      return Uint8List.fromList(
          img.encodeJpg(scaled, quality: op.quality ?? 85));

    case ImageOpType.pngDownscaleLongEdge:
      if (op.maxEdge == null) return op.bytes;
      final decoded = img.decodeImage(op.bytes);
      if (decoded == null) return op.bytes;
      final longEdge =
          decoded.width > decoded.height ? decoded.width : decoded.height;
      if (longEdge <= op.maxEdge!) return op.bytes;
      final scaled = img.copyResize(
        decoded,
        width: decoded.width > decoded.height ? op.maxEdge : null,
        height: decoded.height >= decoded.width ? op.maxEdge : null,
        interpolation: img.Interpolation.linear,
      );
      return Uint8List.fromList(img.encodePng(scaled));

    case ImageOpType.jpegCompress:
      final decoded = img.decodeImage(op.bytes);
      if (decoded == null) {
        throw Exception('Cannot decode image for JPEG compression');
      }
      return Uint8List.fromList(
          img.encodeJpg(decoded, quality: op.quality ?? 70));
  }
}

// ---------------------------------------------------------------------------
// Public API (runs in an isolate)
// ---------------------------------------------------------------------------

/// Compress a JPEG/PNG image to the target quality (0–100) and max dimension.
Future<Uint8List> compressImageIsolate({
  required Uint8List bytes,
  required int maxDimension,
  required int quality,
}) async {
  return compute(_compressImage, _CompressArgs(bytes, maxDimension, quality));
}

/// Downscale an image to fit within [maxWidth] × [maxHeight].
Future<Uint8List> resizeImageIsolate({
  required Uint8List bytes,
  required int maxWidth,
  required int maxHeight,
}) async {
  return compute(_resizeImage, _ResizeArgs(bytes, maxWidth, maxHeight));
}

/// Convert a raw image (any format) to JPEG at the given quality.
Future<Uint8List> toJpegIsolate({
  required Uint8List bytes,
  int quality = 85,
}) async {
  return compute(_toJpeg, _JpegArgs(bytes, quality));
}

/// Convert a raw image (any format) to PNG.
Future<Uint8List> toPngIsolate({required Uint8List bytes}) async {
  return compute(_toPng, bytes);
}

// ---------------------------------------------------------------------------
// Internal (isolate entry points — must be top-level or static)
// ---------------------------------------------------------------------------

class _CompressArgs {
  final Uint8List bytes;
  final int maxDim;
  final int quality;
  const _CompressArgs(this.bytes, this.maxDim, this.quality);
}

Uint8List _compressImage(_CompressArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return args.bytes;

  img.Image result = decoded;
  final longEdge = result.width > result.height ? result.width : result.height;
  if (longEdge > args.maxDim) {
    result = img.copyResize(
      result,
      width: result.width > result.height ? args.maxDim : null,
      height: result.height >= result.width ? args.maxDim : null,
      interpolation: img.Interpolation.linear,
    );
  }
  return Uint8List.fromList(img.encodeJpg(result, quality: args.quality));
}

class _ResizeArgs {
  final Uint8List bytes;
  final int maxW, maxH;
  const _ResizeArgs(this.bytes, this.maxW, this.maxH);
}

Uint8List _resizeImage(_ResizeArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return args.bytes;

  img.Image result = decoded;
  if (result.width > args.maxW || result.height > args.maxH) {
    final scaleW = args.maxW / result.width;
    final scaleH = args.maxH / result.height;
    final scale = scaleW < scaleH ? scaleW : scaleH;
    result = img.copyResize(
      result,
      width: (result.width * scale).round(),
      height: (result.height * scale).round(),
      interpolation: img.Interpolation.linear,
    );
  }
  return Uint8List.fromList(img.encodePng(result));
}

class _JpegArgs {
  final Uint8List bytes;
  final int quality;
  const _JpegArgs(this.bytes, this.quality);
}

Uint8List _toJpeg(_JpegArgs args) {
  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) return args.bytes;
  return Uint8List.fromList(img.encodeJpg(decoded, quality: args.quality));
}

Uint8List _toPng(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  return Uint8List.fromList(img.encodePng(decoded));
}
